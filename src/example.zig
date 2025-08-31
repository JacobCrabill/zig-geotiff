const std = @import("std");
const geotiff = @import("geotiff");
const stb = @import("stb_image");

pub fn main() !void {
    var img: stb.Image = stb.load_image("test.png", null) catch {
        std.debug.print("Test image not found (test.png)\n", .{});
        return error.TestPngNotFound;
    };
    defer img.deinit();

    var gtif = try geotiff.GTiff.init("test.tif");
    defer gtif.deinit();

    try gtif.setOrigin(0, 0, 123.45, 6.789);
    try gtif.setPixelScale(0.5, 0.5);

    const pixels: []const u8 = img.data[0..@intCast(img.width * img.height * img.nchan)];
    try gtif.writeImage(.{
        .width = @intCast(img.width),
        .height = @intCast(img.height),
        .nchan = @intCast(img.nchan),
        .pixel_format = .rgb,
        .bits_per_chan = 8,
        .pixels = pixels,
    });
    std.debug.print("Wrote TIFF image of size {d}x{d} with {d} channels; {d} bytes\n", .{ img.width, img.height, img.nchan, pixels.len });
}
