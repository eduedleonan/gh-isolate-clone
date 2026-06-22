# gh-isolate-clone

Un orquestador interactivo en Bash diseñado para entornos Linux (Arch/Debian) que automatiza la clonación de repositorios de GitHub mediante llaves SSH dedicadas y exclusivas por proyecto.

## Características

- **Auditoría de Entorno**: Escanea el sistema en busca de repositorios de GitHub que utilicen la llave genérica `id_ed25519`.
- **Migración y Aislamiento**: Genera micro-llaves SSH dedicadas con la nomenclatura `id_ed25519_gh_[nombre-repositorio]` y reconfigura los repositorios antiguos de forma automática mediante alias en `~/.ssh/config`.
- **Clonación Segura**: Configura las identidades criptográficas de forma aislada antes de descargar nuevos proyectos, evitando conflictos en estaciones de trabajo multi-cuenta o multi-repositorio.

## Uso rápido

```bash
chmod +x gh-isolate-clone.sh
./gh-isolate-clone.sh
```
