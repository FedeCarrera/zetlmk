# Zettel

Plugin de Neovim para gestionar notas con el método Zettelkasten. Texto plano como fuente de verdad, identificación por ID (no por ruta), todo a demanda.

## Requisitos

- Neovim >= 0.10
- `fzf` (binario) + [`fzf-lua`](https://github.com/ibhagwan/fzf-lua) para el selector por defecto
- `ripgrep` para búsqueda de texto completo (`:Zettel texto`)
- [`nvim-treesitter`](https://github.com/nvim-treesitter/nvim-treesitter) con parser de markdown para detección de tags inline

### Selectores disponibles

| Valor | Plugin necesario |
|---|---|
| `"fzf"` (defecto) | fzf-lua |
| `"telescope"` | telescope.nvim |
| `"select"` | Ninguno (usa `vim.ui.select`) |

## Instalación

Con [lazy.nvim](https://github.com/folke/lazy.nvim), apuntando al directorio local:

```lua
{
  dir = "~/code/zetlmk",
  cmd = "Zettel",
  keys = {
    { "<leader>zn", "<cmd>Zettel nueva<cr>", desc = "Zettel: nueva nota" },
  },
  opts = {
    raiz = "~/zettel",
  },
  config = function(_, opts)
    require("zettel").setup(opts)
  end,
}
```

## Estructura de carpetas

```
zettel/                  raíz configurable
├── *.md                 notas estructura (índices, mapas)
├── inbox/               notas fugaces
├── fuentes/             una nota por libro, video, artículo, etc.
├── permanentes/         ideas propias, atómicas y enlazadas
└── .zettel/
    ├── plantillas/      editables por el usuario
    ├── alias.yaml       alias de tags
    ├── busquedas.yaml   búsquedas guardadas
    ├── index.json       generado (ignorado por git)
    ├── salud.md         generado (ignorado por git)
    └── .gitignore       creado automáticamente
```

## Configuración

```lua
require("zettel").setup({
  raiz = "~/zettel",
  carpetas = {
    inbox = "inbox",
    fuentes = "fuentes",
    permanentes = "permanentes",
  },
  slug_en_nombre = false,       -- true: archivos se llaman ID-slug.md
  selector = "fzf",             -- "fzf" | "telescope" | "select"
  mapeos = true,                -- gd, [[, ]n, [n en notas del zettel
  salud = {
    inbox_dias = 14,            -- fugaces más viejas son advertencia
    nota_larga_palabras = 400,
    nota_varios_subtitulos = 3,
    tag_grande = 30,
  },
  descubrir = {
    nucleo_min_notas = 4,
    tag_maduro_min_notas = 8,
    relacionadas_min_tags = 2,
  },
})
```

## Comandos

Todo se ejecuta como subcomando de `:Zettel` (con autocompletado por tab).

### Escribir

| Comando | Descripción |
|---|---|
| `:Zettel nueva [inbox\|permanente\|estructura]` | Crea una nota. Pide tipo (si no se pasa) y título. |
| `:Zettel fuente` | Crea una fuente. Pide formato (libro, video, articulo u otros definidos por plantilla) y título. |
| `:Zettel borrar` | Borra la nota actual de disco y del índice. Avisa si hay backlinks y pide confirmación. |

### Enlazar y navegar

| Comando | Descripción |
|---|---|
| `:Zettel enlazar` | Abre el selector e inserta `[[ID\|título]]` en la posición del cursor. |
| `:Zettel buscar` | Selector por título sobre todas las notas. Abre la elegida. |
| `:Zettel fuentes` | Selector de fuentes por autor y título. |
| `:Zettel por-tag` | Elige un tag (mostrando cantidad) y después una nota dentro de ese tag. |
| `:Zettel recientes` | Las 30 notas editadas más recientemente. |
| `:Zettel texto` | Búsqueda de texto completo en vivo con ripgrep vía fzf-lua. |

### Conectar y procesar

| Comando | Descripción |
|---|---|
| `:Zettel backlinks` | Ventana flotante con cada nota que enlaza a la actual, mostrando el párrafo de contexto. Enter abre la nota en esa línea. |
| `:Zettel promover` | Mueve una nota de inbox a permanentes. Avisa si no tiene tags o enlaces salientes. |
| `:'<,'>Zettel extraer` | Selección visual: crea una permanente con el texto seleccionado y lo reemplaza por `[[ID\|título]]`. |
| `:Zettel siguiente` | Abre la nota que sigue a la actual (campo `sigue_a`). Si hay varias, abre el selector. |
| `:Zettel anterior` | Abre la nota a la que la actual sigue. |

### Tags

| Comando | Descripción |
|---|---|
| `:Zettel tag` | Agrega un tag a la nota actual, eligiendo de los existentes o escribiendo uno nuevo. |
| `:Zettel tag-renombrar` | Renombra un tag en todas las notas. Muestra las afectadas y pide confirmación. |
| `:Zettel tag-fusionar` | Fusiona un tag en otro. Las notas con ambos no quedan con duplicados. |
| `:Zettel tags-candidatos` | Detecta `#tag` escritos en el cuerpo de la nota y ofrece promoverlos al frontmatter. Ignora títulos, bloques de código, URLs y colores hexadecimales. |

### Editar metadatos

| Comando | Descripción |
|---|---|
| `:Zettel titulo` | Cambia el título de la nota actual. Ofrece actualizar los enlaces en otras notas cuyo texto coincide con el título anterior. |

### Descubrir

| Comando | Descripción |
|---|---|
| `:Zettel vecindario` | Ventana flotante con las notas a uno y dos saltos (enlaces + backlinks). Navegable con `gd` y Enter. |
| `:Zettel menciones` | Títulos de otras notas que aparecen en la actual sin enlace, y notas que mencionan el título de la actual sin enlazarla. |
| `:Zettel relacionadas` | Notas que comparten al menos N tags con la actual y no están enlazadas directamente. |
| `:Zettel azar [tag]` | Abre una permanente al azar, opcionalmente dentro de un tag. |

### Consultas

| Comando | Descripción |
|---|---|
| `:Zettel consulta [query]` | Filtros combinados. Si no se pasa query, pide input. |
| `:Zettel busquedas` | Selector de búsquedas guardadas desde `.zettel/busquedas.yaml`. |

#### Sintaxis de consulta

```
#memoria -#borrador "olvido" en:inbox desde:2026-09 formato:libro
```

| Filtro | Significado |
|---|---|
| `#tag` | Requiere el tag (incluye subtags: `#psicologia` matchea `psicologia/memoria`) |
| `-#tag` | Excluye el tag |
| `"texto"` | Busca texto en título y contenido |
| `palabra` | Igual que `"palabra"` |
| `en:carpeta` | Filtra por carpeta (`inbox`, `permanentes`, `fuentes`, `raiz`) |
| `desde:AAAA-MM` | Notas creadas desde esa fecha (deducida del ID) |
| `formato:X` | Filtra fuentes por formato (`libro`, `video`, `articulo`, etc.) |

### Mantenimiento

| Comando | Descripción |
|---|---|
| `:Zettel salud` | Genera `.zettel/salud.md` con un informe completo y lo abre. Navegable con `gd`. |
| `:Zettel reindexar` | Reconstruye el índice completo desde cero. |

#### Informe de salud

**Errores:** enlaces rotos, IDs duplicados, frontmatter inválido, ID distinto del nombre del archivo, `sigue_a` roto o con ciclos, fuentes sin autor o formato.

**Sugerencias:** permanentes huérfanas, islas, fugaces viejas, notas sin tags, notas largas, tags con una sola nota, tags muy grandes, tags casi duplicados (Levenshtein), fuentes sin permanentes que las enlacen, permanentes con citas sin fuente.

**Oportunidades:** núcleos emergentes (componentes conexos no alcanzados por una estructura), tags maduros (muchas notas sin estructura que los cubra).

## Mapeos

Mapeos locales al buffer, solo en notas del zettel. Se desactivan con `mapeos = false`.

| Mapeo | Modo | Acción |
|---|---|---|
| `gd` | Normal | Seguir el enlace `[[ID\|texto]]` bajo el cursor |
| `[[` | Inserción | Abre el selector, inserta el enlace y vuelve a modo inserción |
| `]n` | Normal | Nota siguiente (`sigue_a`) |
| `[n` | Normal | Nota anterior (`sigue_a`) |

## Alias de tags

Archivo `.zettel/alias.yaml`:

```yaml
stoa: filosofia/estoicismo
mem: psicologia/memoria
```

Los alias se resuelven automáticamente al contar tags y en las consultas. El frontmatter de cada nota conserva lo que el usuario escribió.

## Búsquedas guardadas

Archivo `.zettel/busquedas.yaml`:

```yaml
memoria reciente: #memoria desde:2026-09
inbox pendiente: en:inbox
libros de psicología: formato:libro #psicologia
```

Se acceden con `:Zettel busquedas`.

## Plantillas

Archivos en `.zettel/plantillas/`. El plugin copia las plantillas por defecto si no existen. Editables por el usuario.

Marcadores disponibles: `{{id}}`, `{{titulo}}`, `{{fecha}}`, `{{formato}}`.

```
.zettel/plantillas/
├── fugaz.md
├── permanente.md
├── estructura.md
└── fuentes/
    ├── libro.md
    ├── video.md
    └── articulo.md
```

Para agregar un formato de fuente nuevo, crear un archivo `.md` en `fuentes/`. Aparecerá automáticamente en `:Zettel fuente`.

## Índice

- Se persiste en `.zettel/index.json`.
- Al abrir Neovim, se carga y se comparan fechas de modificación: solo se reindexa lo que cambió.
- Al guardar una nota (`:w`), se reindexa solo ese archivo.
- Los backlinks se calculan en memoria a partir de los enlaces salientes.
- `require("zettel")` no lee el disco hasta el primer uso real.

## Tests

63 tests ejecutables con:

```bash
nvim --headless -u tests/minimal_init.lua -c "lua MiniTest.run()"
```

## Licencia

MIT
