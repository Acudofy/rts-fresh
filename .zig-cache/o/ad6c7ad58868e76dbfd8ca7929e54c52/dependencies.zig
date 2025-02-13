pub const packages = struct {
    pub const @"12209503580bf7234bde4dd26e79d6e7cd8c38e2679e54f9b9ea72ba22834f867531" = struct {
        pub const build_root = "C:\\Users\\joaqu\\AppData\\Local\\zig\\p\\12209503580bf7234bde4dd26e79d6e7cd8c38e2679e54f9b9ea72ba22834f867531";
        pub const build_zig = @import("12209503580bf7234bde4dd26e79d6e7cd8c38e2679e54f9b9ea72ba22834f867531");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
            .{ "xcode_frameworks", "122098b9174895f9708bc824b0f9e550c401892c40a900006459acf2cbf78acd99bb" },
            .{ "emsdk", "1220e8fe9509f0843e5e22326300ca415c27afbfbba3992f3c3184d71613540b5564" },
        };
    };
    pub const @"122098b9174895f9708bc824b0f9e550c401892c40a900006459acf2cbf78acd99bb" = struct {
        pub const available = false;
    };
    pub const @"1220e8fe9509f0843e5e22326300ca415c27afbfbba3992f3c3184d71613540b5564" = struct {
        pub const available = false;
    };
};

pub const root_deps: []const struct { []const u8, []const u8 } = &.{
    .{ "raylib", "12209503580bf7234bde4dd26e79d6e7cd8c38e2679e54f9b9ea72ba22834f867531" },
};
