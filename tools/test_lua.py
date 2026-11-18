from pathlib import Path
from lupa import LuaRuntime

root = Path(__file__).resolve().parent.parent
lua = LuaRuntime(unpack_returned_tuples=True)
lua.globals().arg = lua.table_from({
    1: str(root / "content/mods/ViewpointBathShowerEffects/42/media/lua/client/ViewpointBathShowerEffects.lua")
})
lua.execute((root / "src/test/lua/effects_test.lua").read_text(encoding="utf-8"))
