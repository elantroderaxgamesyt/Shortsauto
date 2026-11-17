# Reglas para la versión final (R8 encoge y renombra el código).
#
# WorkManager (lo usa el SDK de anuncios de Google) crea su base de datos Room por
# reflexión buscando la clase "WorkDatabase_Impl" por su nombre. Si R8 la renombra o le
# quita el constructor, la app se cierra al abrirse con:
#   Failed to create an instance of androidx.work.impl.WorkDatabase
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-keep class androidx.work.impl.WorkDatabase_Impl { *; }
-keep class androidx.work.** { *; }
-keep class androidx.room.** { *; }
-dontwarn androidx.room.paging.**
