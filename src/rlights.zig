pub const c = @cImport({
    @cDefine("RLIGHTS_IMPLEMENTATION", "");
    @cInclude("rlights.h");
});
