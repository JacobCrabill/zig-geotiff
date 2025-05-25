const std = @import("std");
const geotiff = @import("geotiff");

pub fn main() !void {
    var gtif = geotiff.GTiff.init("test.tif") orelse return error.GTiffError;
    defer gtif.deinit();
    gtif.setOrigin(123.45, 678.9);
    gtif.setPixelScale(0.5, 0.5);
}
