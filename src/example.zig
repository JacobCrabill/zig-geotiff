const std = @import("std");
const geotiff = @import("geotiff");
const stb = @import("stb_image");

pub fn main() !void {
    var img: stb.Image = try stb.load_image("test.png", null);
    defer img.deinit();

    var gtif = geotiff.GTiff.init("test.tif") orelse return error.GTiffError;
    defer gtif.deinit();

    try gtif.setOrigin(123.45, 678.9);
    try gtif.setPixelScale(0.5, 0.5);

    const pixels: []const u8 = img.data[0..@intCast(img.width * img.height * img.nchan)];
    std.debug.print("Image of size {d}x{d} with {d} channels; {d} bytes\n", .{ img.width, img.height, img.nchan, pixels.len });
    try gtif.writeImage(@intCast(img.width), @intCast(img.height), @intCast(img.nchan), pixels);
}
