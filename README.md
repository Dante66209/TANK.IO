<h1 align="center">TANK.IO</h1>

<p align="center">
  <strong>Arena táctica 2D de combate de tanques para 5–30 combatientes (Web / itch.io, Escritorio y Multijugador Online WebSocket) desarrollada en Godot 4.6.</strong>
</p>

---

## Características principales

- **Combate de tanques con chasis y torreta independientes:** conducción omnidireccional suave (`BASE_SPEED = 240 px/s`), apuntado libre con el ratón, **Dash táctico** (`1.6x`) con barra de estamina, **minas de proximidad `[Q]`** (hasta 3 cargas) y balas con físicas de rebote.
- **Arena masiva `6400x6400` (5–30 jugadores):** soporta partidas locales contra bots con IA táctica o partidas multijugador en línea con sincronización autoritativa por servidor.
- **Niebla de guerra (Fog of War):** visibilidad dinámica por radio de visión (`560 px`) con radar/minimapa táctico en tiempo real y pings de disparos.
- **Entorno destructible y eventos dinámicos:**
  - **48 barriles explosivos** con daño radial que atraviesa cobertura y reacciones en cadena.
  - **Muros de madera destructibles** que se agrietan y reaparecen tras un tiempo de espera.
  - **Barrera de Morteros:** bombardeos periódicos sobre la arena con telegrafía visual/sonora y alertas en el HUD.
  - **Muerte Súbita:** cierre progresivo de zona segura en los últimos 30 segundos con reapariciones desactivadas y transición automática a **Modo Espectador**.
- **6 Power-Ups en arena:**
  - `HEALTH` (+40 vida)
  - `SHIELD` (+50 escudo absorbente)
  - `RAPID_FIRE` (cadencia acelerada)
  - `RICOCHET` (20 proyectiles con rebote)
  - `SPEED_BOOST` (velocidad x2 + música dinámica)
  - `CLUSTER_MINES` (minas racimo)
- **Interfaz pensada para Web (itch.io):** set de 16 íconos vectoriales SVG en [Assets/Icons/](Assets/Icons/) (sin dependencia de fuentes emoji del sistema), personalizador de tanque en el menú (nombre + 10 colores tácticos), lobby con gestión de bots/líder, medallas de racha de bajas, feed de bajas y podio final con tabla completa de posiciones.

---

## Controles

| Acción | Tecla / Entrada |
| :--- | :--- |
| Mover chasis | `W` `A` `S` `D` |
| Apuntar torreta | Ratón |
| Disparar | `Clic Izquierdo` o `Espacio` |
| Dash / Sprint | `Shift` o `Clic Derecho` |
| Lanzar mina | `Q` |
| Cambiar objetivo (Espectador) | `A` / `D` o `Clic Izquierdo / Derecho` |
| Pausa / Configuración | `Esc` |

---

## Multijugador Online (Servidor Dedicado WebSocket)

El juego utiliza un servidor dedicado autoritativo sobre `WebSocketMultiplayerPeer` ([network_manager.gd](Scripts/Core/network_manager.gd) y [match_network_sync.gd](Scripts/Core/match_network_sync.gd)), compatible con clientes Web HTTPS (`wss://` en **itch.io**) y clientes de escritorio (`ws://` o `wss://`).

### 1. Despliegue en la nube gratis con Render.com (Docker)

El repositorio ya incluye [Dockerfile](Dockerfile), [.dockerignore](.dockerignore), [render.yaml](render.yaml) y [server_proxy.py](server_proxy.py):

1. Sube tu repositorio a GitHub.
2. En **Render.com** -> **New +** -> **Blueprint** (o **Web Service** con entorno **Docker**, plan **Free** y **Health Check Path: `/health`**).
3. `server_proxy.py` inicia Godot headless en `127.0.0.1:7777` y expone `0.0.0.0:$PORT` (`10000`) respondiendo `HTTP 200 OK` en `/health` y redirigiendo tráfico WebSocket hacia Godot.
4. En el cliente (por ejemplo en itch.io), pega tu URL `wss://tu-app.onrender.com` en **SERVIDOR DEDICADO ONLINE** y pulsa **CONECTAR**.
   - *Nota:* El cliente reintenta automáticamente durante hasta **75 s** si el servicio gratuito de Render estaba suspendido por inactividad (~50 s de arranque en frío).

### 2. Ejecución local del servidor dedicado (Godot 4.6)

```powershell
Godot_v4.6-stable_win64_console.exe --headless --path . -- --server --port=7777 --room="Sala TANK.IO" --max-players=10
```

**Flags CLI y variables de entorno soportadas:**
- `--server` / `DEDICATED_SERVER=1`: inicia en modo servidor dedicado.
- `--port=7777` / `PORT`: puerto de escucha (`1024..65535`).
- `--bind=*` / `BIND_ADDRESS`: dirección de escucha (`*`, `0.0.0.0`, `127.0.0.1`).
- `--room="Nombre"` / `ROOM_NAME`: nombre de la sala (máx. 28 caracteres).
- `--max-players=10` / `MAX_PLAYERS`: capacidad (`5..30`).
- `--autofill` / `AUTOFILL_BOTS=true`: rellena espacios libres con bots.
- `--auto-start` / `AUTO_START=true`: inicia la partida al llenarse la sala.

---

## Exportación Web para itch.io

El preset **Web** configurado usa exportación **Single-threaded** (`variant/thread_support=false`) para funcionar directamente en el navegador sin requerir cabeceras `SharedArrayBuffer`:

```powershell
Godot_v4.6-stable_win64_console.exe --headless --path . --export-release "Web" "build_web/index.html"
```

*(Comprime el contenido de `build_web/` en un `.zip` con `index.html` en la raíz para subirlo a itch.io).*

---

## Pruebas automatizadas

El proyecto incluye una suite E2E headless en [Tests/test_runner.tscn](Tests/test_runner.tscn) organizada en 8 niveles (mecánicas base R1–R8, casos límite, combinaciones, simulaciones completas, mejoras de gameplay/UI, flujos de menús/lobby, lobby WebSocket y sincronización autoritativa de partida):

```powershell
Godot_v4.6-stable_win64_console.exe --headless --path . res://Tests/test_runner.tscn
```

---

## Estructura del proyecto

- `Assets/Icons/`: Set de 16 íconos vectoriales SVG (`check`, `star`, `hourglass`, `alert`, `crown`, `trophy`, `bolt`, `ricochet`, `mine`, `mine_cluster`, `mine_empty`, `mortar`, `eye`, `biohazard`, `chevron_left`, `chevron_right`).
- `Scenes/`: Escenas de juego (`main_menu.tscn`, `match_browser_panel.tscn`, `main_game.tscn`, `hud.tscn`, `podium_screen.tscn`, tanques, barriles, muros, power-ups).
- `Scripts/Core/`: Managers globales (`game_events.gd`, `game_settings.gd`, `network_manager.gd`, `match_manager.gd`, `match_network_sync.gd`, `spawn_manager.gd`, `mortar_manager.gd`, `sound_manager.gd`).
- `Scripts/Entities/`: Tanques, torreta/chasis, proyectiles, minas, barriles, power-ups.
- `Scripts/UI/`: Menú principal, navegador de salas/lobby, HUD, minimapa, podio, pausa, ajustes.
- `Tests/`: Runner maestro y suites de verificación automática.
