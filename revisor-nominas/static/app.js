const $ = (s) => document.querySelector(s);
const estado = { plan: "free", archivo: null, resultado: null, historial: [] };

const eur = (n) => n == null ? "—" : n.toLocaleString("es-ES", { style: "currency", currency: "EUR" });
const esc = (t) => String(t ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const ETQ = { ok: "Bien", aviso: "Revisar", error: "Error" };
const VER = {
  correcta: ["✅", "Tu nómina parece correcta"],
  revisar: ["⚠️", "Hay puntos que conviene revisar"],
  incorrecta: ["❌", "Hemos encontrado errores"],
  ilegible: ["🔍", "No se ha podido leer bien la nómina"],
};

// ---- Plan ----
function ponerPlan(plan) {
  estado.plan = plan;
  document.body.classList.toggle("pro", plan === "pro");
  document.querySelectorAll(".plan").forEach((b) => b.classList.toggle("activo", b.dataset.plan === plan));
  document.querySelectorAll(".col").forEach((c) => c.classList.toggle("activo", c.dataset.plan === plan));
  $("#campo-codigo").hidden = plan !== "pro";
  $("#btn-analizar").textContent = plan === "pro" ? "Revisión completa (Pro)" : "Revisar nómina gratis";
}
document.querySelectorAll(".plan").forEach((b) => b.onclick = () => ponerPlan(b.dataset.plan));
document.querySelectorAll(".col").forEach((c) => c.onclick = () => ponerPlan(c.dataset.plan));

// ---- Archivo ----
function ponerArchivo(f) {
  if (!f) return;
  estado.archivo = f;
  $("#zona").classList.add("lleno");
  $("#zona-texto").textContent = `📄 ${f.name} (${(f.size / 1024).toFixed(0)} KB)`;
  $("#btn-analizar").disabled = false;
}
$("#archivo").onchange = (e) => ponerArchivo(e.target.files[0]);
const zona = $("#zona");
["dragenter", "dragover"].forEach((ev) => zona.addEventListener(ev, (e) => { e.preventDefault(); zona.classList.add("encima"); }));
["dragleave", "drop"].forEach((ev) => zona.addEventListener(ev, (e) => { e.preventDefault(); zona.classList.remove("encima"); }));
zona.addEventListener("drop", (e) => ponerArchivo(e.dataTransfer.files[0]));

function mostrar(id) {
  for (const s of ["#subida", "#cargando", "#resultado"]) $(s).hidden = s !== id;
}
function error(msg) { const e = $("#error"); e.textContent = msg; e.hidden = !msg; }

// ---- Análisis ----
$("#form").onsubmit = async (e) => {
  e.preventDefault();
  if (!estado.archivo) return;
  error("");
  mostrar("#cargando");
  const fd = new FormData();
  fd.append("archivo", estado.archivo);
  fd.append("plan", estado.plan);
  fd.append("codigo", $("#codigo").value);
  try {
    const r = await fetch("/api/analizar", { method: "POST", body: fd });
    const j = await r.json();
    if (!r.ok) throw new Error(j.detail || "Error al analizar");
    estado.resultado = j;
    estado.historial = [];
    pintarInforme(j);
    mostrar("#resultado");
  } catch (err) {
    mostrar("#subida");
    error(err.message);
  }
};

function puntos(lista) {
  return lista.map((p) => `
    <div class="punto">
      <span class="etiqueta e-${p.estado}">${ETQ[p.estado]}</span>
      <div><b>${esc(p.concepto)}</b>
        <p>${esc(p.explicacion)}</p>
        ${p.que_hacer && p.que_hacer !== "Nada." ? `<p class="hacer">👉 ${esc(p.que_hacer)}</p>` : ""}
      </div>
    </div>`).join("");
}

function tablaCalculos(c) {
  if (!c.length) return "";
  return `<div class="scroll"><table class="tabla">
    <tr><th>Comprobación</th><th class="num">En nómina</th><th class="num">Calculado</th><th></th></tr>
    ${c.map((x) => `<tr><td>${esc(x.concepto)}</td><td class="num">${typeof x.importe_nomina === "number" && x.concepto.startsWith("Porcentaje") ? x.importe_nomina + " %" : eur(x.importe_nomina)}</td>
      <td class="num">${x.concepto.startsWith("Porcentaje") ? x.importe_esperado + " %" : eur(x.importe_esperado)}</td>
      <td><span class="etiqueta e-${x.estado}">${ETQ[x.estado]}</span></td></tr>`).join("")}
  </table></div>`;
}

function pintarInforme({ plan, informe: inf, calculos, demo }) {
  $("#aviso-demo").hidden = !demo;
  const d = inf.datos;
  const [ico, tit] = VER[inf.veredicto];
  let h = `
    <div class="veredicto v-${inf.veredicto}"><span class="icono">${ico}</span>
      <div><b>${tit}</b>${esc(d.periodo || "")}${d.empresa ? " · " + esc(d.empresa) : ""}</div></div>
    <p>${esc(inf.resumen)}</p>
    <div class="cifras">
      <div class="cifra"><small>Total devengado</small><span>${eur(d.total_devengado)}</span></div>
      <div class="cifra"><small>Deducciones</small><span>${eur(d.total_deducciones)}</span></div>
      <div class="cifra"><small>Líquido a percibir</small><span>${eur(d.liquido)}</span></div>
    </div>`;

  if (plan === "free") {
    h += `<h3>Lo más importante</h3>${puntos(inf.puntos)}
      <h3>Comprobación de cálculos</h3>${tablaCalculos(calculos)}
      <div class="upsell"><b>¿Quieres la revisión completa?</b><br>
        Con Pro recalculamos cada cotización y el IRPF, te explicamos cada línea de la nómina,
        te damos las preguntas para RRHH y un borrador de reclamación si hay errores.<br>
        <button id="ir-pro">Probar Pro con esta nómina</button></div>`;
  } else {
    h += `<h3>Revisión concepto a concepto</h3>${puntos(inf.comprobaciones)}
      <h3>Cálculos recalculados por la app</h3>${tablaCalculos(calculos)}
      <h3>Detalle de la nómina</h3>
      <div class="scroll"><table class="tabla">
        <tr><th>Devengos</th><th class="num">Importe</th></tr>
        ${d.devengos.map((l) => `<tr><td>${esc(l.concepto)}</td><td class="num">${eur(l.importe)}</td></tr>`).join("")}
        <tr><th>Deducciones</th><th class="num">Importe</th></tr>
        ${d.deducciones.map((l) => `<tr><td>${esc(l.concepto)}${l.porcentaje != null ? ` (${l.porcentaje} %)` : ""}</td><td class="num">${eur(l.importe)}</td></tr>`).join("")}
      </table></div>
      <details open><summary>Qué significa cada concepto</summary>${puntos(inf.explicacion_conceptos)}</details>
      <h3>Recomendaciones</h3><ul>${inf.recomendaciones.map((r) => `<li>${esc(r)}</li>`).join("")}</ul>
      <h3>Preguntas para RRHH o la gestoría</h3><ul>${inf.preguntas_para_rrhh.map((r) => `<li>${esc(r)}</li>`).join("")}</ul>
      ${inf.borrador_reclamacion ? `<h3>Borrador de reclamación</h3><pre class="borrador">${esc(inf.borrador_reclamacion)}</pre>
        <button id="copiar">Copiar texto</button>` : ""}
      <p class="letra-pequena">Confianza del análisis: <b>${esc(inf.confianza)}</b>. ${esc(inf.limitaciones)}</p>`;
  }
  h += `<p class="letra-pequena">Informe orientativo generado con IA. Para reclamar formalmente, consulta con un graduado social, sindicato o abogado laboralista.</p>`;
  $("#informe").innerHTML = h;

  $("#btn-imprimir").hidden = plan !== "pro";
  $("#mensajes").innerHTML = "";
  actualizarLimite();
  const irPro = $("#ir-pro");
  if (irPro) irPro.onclick = () => { ponerPlan("pro"); $("#form").requestSubmit(); };
  const copiar = $("#copiar");
  if (copiar) copiar.onclick = () => navigator.clipboard.writeText(inf.borrador_reclamacion).then(() => copiar.textContent = "¡Copiado!");
}

// ---- Chat ----
function actualizarLimite() {
  const max = estado.resultado.preguntas_chat;
  const usadas = estado.historial.filter((m) => m.role === "user").length;
  $("#chat-limite").textContent = max ? `Versión gratuita: te quedan ${Math.max(0, max - usadas)} de ${max} preguntas.` : "Preguntas ilimitadas.";
  const agotado = max && usadas >= max;
  $("#pregunta").disabled = agotado;
  $("#form-chat button").disabled = agotado;
  if (agotado) $("#pregunta").placeholder = "Pásate a Pro para seguir preguntando";
}

function burbuja(role, texto) {
  const div = document.createElement("div");
  div.className = `msg ${role}`;
  div.textContent = texto;
  $("#mensajes").appendChild(div);
  return div;
}

$("#form-chat").onsubmit = async (e) => {
  e.preventDefault();
  const q = $("#pregunta").value.trim();
  if (!q) return;
  $("#pregunta").value = "";
  burbuja("user", q);
  estado.historial.push({ role: "user", content: q });
  actualizarLimite();
  const div = burbuja("assistant", "…");
  try {
    const r = await fetch("/api/chat", {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ plan: estado.resultado.plan, codigo: $("#codigo").value,
        informe: { ...estado.resultado.informe, calculos_app: estado.resultado.calculos }, historial: estado.historial }),
    });
    if (!r.ok) { const j = await r.json(); throw new Error(j.detail); }
    const lector = r.body.getReader(); const dec = new TextDecoder(); let texto = "";
    for (;;) {
      const { done, value } = await lector.read();
      if (done) break;
      texto += dec.decode(value, { stream: true });
      div.textContent = texto;
    }
    estado.historial.push({ role: "assistant", content: texto });
  } catch (err) {
    div.textContent = err.message || "Error";
    estado.historial.pop();
  }
  actualizarLimite();
};

$("#btn-nueva").onclick = () => { mostrar("#subida"); error(""); };
$("#btn-imprimir").onclick = () => window.print();

fetch("/api/estado").then((r) => r.json()).then((j) => { $("#aviso-demo").hidden = !j.demo; });
ponerPlan("free");
