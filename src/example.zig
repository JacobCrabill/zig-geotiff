const std = @import("std");
const geotiff = @import("geotiff");
const stb = @import("stb_image");

pub fn main() !void {
    var img: stb.Image = try stb.load_image("test.png", null);
    defer img.deinit();

    var gtif = geotiff.GTiff.init("test.tif") orelse return error.GTiffError;
    defer gtif.deinit();

    try gtif.setOrigin(123.45, 6.789);
    try gtif.setPixelScale(0.5, 0.5);

    const pixels: []const u8 = img.data[0..@intCast(img.width * img.height * img.nchan)];
    try gtif.writeImage(.{
        .width = @intCast(img.width),
        .height = @intCast(img.height),
        .nchan = @intCast(img.nchan),
        .pixels = pixels,
        .format = .rgb,
    });
    std.debug.print("Wrote TIFF image of size {d}x{d} with {d} channels; {d} bytes\n", .{ img.width, img.height, img.nchan, pixels.len });
}
