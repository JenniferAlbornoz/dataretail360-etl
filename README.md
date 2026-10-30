# DataRetail 360 · Pipeline ETL y Data Warehouse (IDY1102)

Caso semestral de **Estructuras y Visualización de Datos** (Duoc UC, sección 001_V).
Jennifer Albornoz · Francisca Blanchard.

Pipeline ETL en Python que integra las ventas de tiendas físicas, e-commerce y un sistema legado, las limpia y valida,
y las carga en un **Data Warehouse dimensional (Kimball)** sobre **SQL Server**, organizado con **arquitectura Medallion**
(Bronze → Silver → Gold) y publicado en **4 data marts** por área de negocio.

## Contenido

```
dataretail360-etl/
├── notebooks/
│   └── dataretail360_pipeline.ipynb   ← todo el proceso en un solo notebook
├── sql/
│   └── consultas_evidencia_ssms.sql   ← consultas para revisar la carga en SSMS
├── data/
│   ├── fuente/                         ← ENTRADA: 18 archivos sucios (ventas, maestros, inventario) + manifest.json
│   ├── salida/                         ← SALIDA: ventas_limpias_integradas.csv + diccionario_datos.xlsx
│   └── control/                        ← referencia de control para la validación final
├── requirements.txt
├── .env.example                       ← plantilla de configuración (copiar como .env)
└── .gitignore
```

## Qué hace el notebook

| Sección | Contenido |
|---|---|
| 1 | Configuración, conexión a SQL Server (o SQLite de respaldo) y logging |
| 2 | Genera los archivos de los sistemas de origen con semilla fija: datos basados en la guía 2.3.5 (catálogo, sucursales, canales, errores de calidad) y completados por el equipo. Incluye la tabla de errores insertados con su proporción |
| 3 | Crea los esquemas `bronze`, `silver`, `gold`, `audit`, `sem` y sus tablas (PK y FK) |
| 4 | Framework: registro de etapas, auditoría, cuarentena de rechazados, transacciones |
| 5 | Bronze: ingesta trazable + mapa de fuentes (sistema → archivo → Bronze → Silver → Gold) |
| 6 | Silver: reglas de calidad, homologación de códigos entre sistemas, seudonimización del RUT |
| 7 | Gold: modelo **estrella** con dos hechos (ventas e inventario) y dimensiones SCD 0, 1, 2 y 3 |
| 8 | Ejecuta el lote 1 (ene–jun 2025 + histórico 2018) y el lote 2 (jul–dic 2025, con cambios en los maestros) |
| 9 | Agregados producto–sucursal–mes, 4 data marts (Comercial, Marketing, Finanzas, Operaciones), vista integrada, capa semántica para IA y diccionario de datos |
| 10 | 30 controles de calidad, correcciones por fuente y errores insertados vs detectados |
| 11 | Evidencias: linaje, efecto SCD, re-ejecución sin duplicados (idempotencia), manejo de errores, validación contra el origen, consultas de negocio |
| 12 | Dataset limpio final: los 18 archivos sucios salen como un solo CSV limpio e integrado |
| 13 | Resumen de ejecución y huella del resultado (reproducibilidad) |

## Cómo ejecutarlo

1. **SQL Server**: instalar SQL Server 2022 Express (instalación *Básica*, instancia `SQLEXPRESS`), SSMS y el
   [ODBC Driver 18 for SQL Server](https://learn.microsoft.com/sql/connect/odbc/download-odbc-driver-for-sql-server).
2. Crear el entorno e instalar dependencias. Si la carpeta del proyecto tiene una ruta muy larga, Windows puede fallar
   al instalar numpy ("nombre de archivo demasiado largo"); por eso se recomienda crear el entorno en una ruta corta:
   ```bash
   py -m venv C:\venvs\dr360
   C:\venvs\dr360\Scripts\python -m pip install -r requirements.txt
   ```
3. Copiar `.env.example` como `.env` y ajustar `MSSQL_SERVER` (el *Server name* de SSMS, por ejemplo `localhost\SQLEXPRESS`)
   y `MSSQL_DRIVER` (`ODBC Driver 18 for SQL Server`). Con autenticación de Windows, usuario y contraseña quedan vacíos.
   La base `DataRetail360` se crea sola.
4. Abrir `notebooks/dataretail360_pipeline.ipynb` en VS Code, elegir el kernel `C:\venvs\dr360\Scripts\python.exe`
   y ejecutar **Run All** (en SQL Server Express tarda unos 7 minutos).
5. En SSMS (conectar con *Trust server certificate* marcado), abrir `sql/consultas_evidencia_ssms.sql` y ejecutar las consultas.

**Resultado esperado:** 108.932 líneas en `gold.fact_ventas`, 79.956 en `gold.fact_inventario`, 1.822 registros en cuarentena
y la huella del resultado `5c997dad0db7b4f2`, idéntica en cada ejecución con el mismo dataset.

**Dataset:** ya viene incluido en `data/fuente/`. El notebook lo reutiliza y verifica su integridad con `manifest.json`
(SHA-256 de cada archivo). Para generarlo de nuevo (por ejemplo, con otra `SEMILLA`), poner `REGENERAR_FUENTES = True` en la sección 1.

**Respaldo:** si SQL Server no está disponible, poner `DR360_MOTOR=sqlite` en el `.env`; el mismo notebook corre sobre SQLite.

## Buenas prácticas aplicadas

- Credenciales y sal de seudonimización en `.env`, fuera del código y del repositorio.
- El RUT nunca llega a Silver ni a Gold: se reemplaza por SHA-256 con sal (Ley 19.628 / 21.719).
- Cada lote se carga en una transacción: si algo falla, no quedan datos a medias.
- Re-ejecutar un lote no duplica datos (carga idempotente): Bronze reemplaza la copia del archivo, Silver y los hechos reemplazan las filas del lote y un lote antiguo no pisa maestros más nuevos.
- La huella del resultado es idéntica en cada ejecución con el mismo dataset (reproducible).
- Los dos hechos (ventas e inventario) se agregan a producto–sucursal–mes antes de unirlos: las cifras no se duplican.
- Cada fila de los hechos guarda archivo, fila de origen, lote e ID de ejecución (linaje).
- Montos en pesos enteros y columnas de dinero en `DECIMAL(18,2)`.
- Diccionario de datos completo de todas las capas en `data/salida/diccionario_datos.xlsx` y en `sem.diccionario_datos`.
