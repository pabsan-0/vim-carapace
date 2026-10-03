# vim-carapace

Shell completion inside any Vim buffer, powered by [carapace](https://github.com/carapace-sh/carapace-bin).

<!-- " TODO exception to skip a leader (word[0]) via ignore rule -->
<!-- " TODO check ALL possible commands using shellcmd (no carapace slowness) -->
<!-- " TODO skip UPPERCASE environment vairables -->
<!-- " TODO add completion for ENV variables via $ -->

## Requirements

- Vim 8.1 or newer
- `carapace` available on `$PATH`

## Installation

```vim
Plug 'pabsan-0/vim-carapace'
```

## Usage

While in insert mode, press `<C-x><C-u>` on a shell command to have it autocompleted, whether it's a command name, a subcommand, or a flag value.

```vim
git che<C-x><C-u>
git checkout

git checkout ma<C-x><C-u>
git checkout master

curl --<C-x><C-u>          " Recalls weird kwargs
docker run <C-x><C-u>      " Recalls the name of your image
```

Lines joined by a trailing `\` are treated a single command.

```vim
./gst-env.py                 \
    gst-launch-1.0 -vvv      \
        videotestsrc         \
            ! videoconvert   \
            ! xvim<C-x><C-u>
```

When nesting commands, the first word of each line will attempt autocompletion in sequence, starting from the highest scope.

See details in the [plugin documentation](./doc/carapace.txt) for more.

## Configuration

All variables are optional.

|: Variable                    | Description                                                                  | Default           |
| ---                           | ---                                                                          | ---               |
| `g:carapace_enabled`          | Set to 0 to disable the plugin entirely.                                     | `1`               |
| `g:carapace_binary`           | Path or name of the carapace executable.                                     | `'carapace'`      |
| `g:carapace_bridges`          | Value for `$CARAPACE_BRIDGES`, set only if that variable is unset.           | `'zsh,fish,bash'` |
| `g:carapace_leader_fallbacks` | Maximum number of extra command candidates tried per completion.             | `2`               |
| `g:carapace_overrides`        | Replacing rules for custom 'carapace' behavior. See [Overrides](#overrides). | {}                |

## Overrides

Overrides live in your `.vimrc` and help `carapace` when it can't complete by default. They modify the command string that is passed to `carapace` for completion in a generic manner. Their whole point is to allow users to handle their edge-cases with a few config lines.

Here's an example in which we define overrides for a few target commands, setting a Rule and passing arguments to it.

```vim
let g:carapace_overrides = {
    \ 'gst-launch-1.0': [['DropWithValue', '--gst-plugin-load']],
    \ 'batcat':         [['Replace', 'batcat', 'bat']],
    \ 'fdfind':         [['Replace', 'fdfind', 'fd']],
    \ }
```

The available Rules are:

```
Drop(pattern)                 Removes every matching argument
DropWithValue(pattern)        Removes a matching argument and its value
DropFrom(pattern)             Removes the first match and everything after it
Replace(pattern, replacement) Replaces a matching argument
InsertAfter(pattern, token)   Inserts token after the first match
KeepFirst(n)                  Keeps only the first n arguments
```
