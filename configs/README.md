# Example config files for cligen

To try out these config files, you can just copy them to your
`${XDG_CONFIG_HOME:-$HOME/.config}/cligen/` directory.

## Nim Configuration syntax configs

Default compiles will uses Nim stdlib parsecfg and look for cligen config files
in `${XDG_CONFIG_HOME:-$HOME/.config}/cligen/config` and then look for
`${XDG_CONFIG_HOME:-$HOME/.config}/cligen`.

## TOML Configuration syntax configs

Compiling your projects with `-d:cgCfgToml` will automatically fetch the config
from `${XDG_CONFIG_HOME:-$HOME/.config}/cligen/config.toml` or if that does not
exist `${XDG_CONFIG_HOME:-$HOME/.config}/cligen.toml`

## $CLIGEN

In addition to the above default search path for config files, a CL user can
also set, e.g., `CLIGEN=$HOME/.cligenrc`.
