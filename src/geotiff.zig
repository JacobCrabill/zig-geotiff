const std = @import("std");
const c = @cImport({
    @cInclude("geotiffio.h");
    @cInclude("xtiffio.h");
});

pub const ModelType = enum(u8) {
    /// Projection Coordinate System
    ModelTypeProjected = 1,
    /// Geographic latitude-longitude System
    ModelTypeGeographic = 2,
    /// Geocentric (X,Y,Z) Coordinate System
    ModelTypeGeocentric = 3,
};

/// Handle the return value of a C function call
fn tryCall(res: c_int) !void {
    if (res < 0) {
        return error.CError;
    }
}

pub const GTiff = struct {
    tif: *c.TIFF = undefined,
    gtif: *c.GTIF = undefined,

    /// Initialize a new GeoTiff file.
    pub fn init(file: []const u8) ?GTiff {
        var gtif = GTiff{};

        // TIFF-level descriptor
        if (c.XTIFFOpen(@ptrCast(file), "w")) |tif| {
            gtif.tif = tif;
        } else {
            std.debug.print("failed in XTIFFOpen\n", .{});
            return null;
        }

        // GeoKey-level descriptor
        if (c.GTIFNew(gtif.tif)) |g| {
            gtif.gtif = g;
        } else {
            std.debug.print("failed in GTIFNew\n", .{});
            c.TIFFClose(gtif.tif);
            return null;
        }

        return gtif;
    }

    /// Close the TIFF file.
    pub fn deinit(self: *GTiff) void {
        c.TIFFClose(self.tif);
    }

    /// Set a key value as a u16 (short)
    pub fn SetKeyShort(self: *GTiff, key: u32, value: u16) !void {
        try tryCall(c.GTIFKeySet(self.gtif, key, c.TYPE_SHORT, 1, value));
    }

    /// Set a key value as a double
    pub fn SetKeyDouble(self: *GTiff, key: u32, value: f64) !void {
        try tryCall(c.GTIFKeySet(self.gtif, key, c.TYPE_DOUBLE, 1, value));
    }

    /// Set a key value as an ASCII string
    pub fn SetKeyAscii(self: *GTiff, key: u32, value: []const u8) !void {
        try tryCall(c.GTIFKeySet(self.gtif, key, c.TYPE_ASCII, 0, value));
    }

    /// Write the image data to the TIFF file.
    /// This additionally sets the width, height, and pixel format metadata.
    pub fn writeImage(self: *GTiff, width: u32, height: u32, nchan: u8, pixels: []const u8) !void {
        const nbytes: u32 = nchan * width * height;
        std.debug.assert(pixels.len == nbytes);

        // Basic metadata
        try tryCall(c.TIFFSetField(self.tif, c.TIFFTAG_COMPRESSION, c.COMPRESSION_NONE));
        try tryCall(c.TIFFSetField(self.tif, c.TIFFTAG_PHOTOMETRIC, c.PHOTOMETRIC_MINISBLACK));
        try tryCall(c.TIFFSetField(self.tif, c.TIFFTAG_PLANARCONFIG, c.PLANARCONFIG_CONTIG));

        // Image metadata: Width, Height, Number of channels (samples) per pixel, bit size of each channel (sample)
        try tryCall(c.TIFFSetField(self.tif, c.TIFFTAG_IMAGEWIDTH, width));
        try tryCall(c.TIFFSetField(self.tif, c.TIFFTAG_IMAGELENGTH, height));
        try tryCall(c.TIFFSetField(self.tif, c.TIFFTAG_SAMPLESPERPIXEL, @as(u16, nchan)));
        try tryCall(c.TIFFSetField(self.tif, c.TIFFTAG_BITSPERSAMPLE, @as(u16, 8)));

        // Basic GeoTIFF tags
        try tryCall(c.GTIFKeySet(self.gtif, c.GTRasterTypeGeoKey, c.TYPE_SHORT, 1, c.RasterPixelIsArea));
        try tryCall(c.GTIFKeySet(self.gtif, c.GeogAngularUnitsGeoKey, c.TYPE_SHORT, 1, c.Angular_Degree));
        try tryCall(c.GTIFKeySet(self.gtif, c.GeogLinearUnitsGeoKey, c.TYPE_SHORT, 1, c.Linear_Meter));

        const stride: u32 = width * nchan;
        var i: u32 = 0;
        while (i < height) : (i += 1) {
            const line: *anyopaque = @ptrCast(@constCast(&pixels[i * stride]));
            try tryCall(c.TIFFWriteScanline(self.tif, line, i, 0));
        }
    }

    /// Set the raster-space to model-space mapping.
    /// Sets the top-left of the raster space (pixel 0,0) to the model-space (x,y) position.
    /// We are ignoring multi-valued raster images (K index) and 3D mappings.
    pub fn setOrigin(self: *GTiff, x: f64, y: f64) !void {
        // [i, j, k, x, y, z]
        const tiepoints: [6]f64 = .{ 0, 0, 0, x, y, 0 };
        try tryCall(c.TIFFSetField(self.tif, c.TIFFTAG_GEOTIEPOINTS, @as(u32, 6), &tiepoints[0]));
    }

    /// Set the pixel scale
    pub fn setPixelScale(self: *GTiff, xscale: f64, yscale: f64) !void {
        const pixscale: [3]f64 = .{ xscale, yscale, 0 };
        try tryCall(c.TIFFSetField(self.tif, c.TIFFTAG_GEOPIXELSCALE, @as(u32, 3), &pixscale[0]));
    }
};

//void SetUpTIFFDirectory(TIFF *tif);
//void SetUpGeoKeys(GTIF *gtif);
//void WriteImage(TIFF *tif);
//
//#define WIDTH 20L
//#define HEIGHT 20L
//
//int main()
//{
//  const char *fname = "newgeo.tif";
//
//  TIFF *tif=XTIFFOpen(fname,"w");  /* TIFF-level descriptor */
//  if (!tif) {
//    printf("failure in makegeo\n");
//    return -1;
//  }
//
//  GTIF *gtif = GTIFNew(tif);  /* GeoKey-level descriptor */
//  if (!gtif)
//  {
//    printf("failure in makegeo\n");
//    printf("failed in GTIFNew\n");
//    TIFFClose(tif);
//    return -1;
//  }
//
//  SetUpTIFFDirectory(tif);
//  SetUpGeoKeys(gtif);
//  WriteImage(tif);
//
//  GTIFWriteKeys(gtif);
//  GTIFFree(gtif);
//  XTIFFClose(tif);
//  return 0;
//}
//
//
//void SetUpTIFFDirectory(TIFF *tif)
//{
//  TIFFSetField(tif,TIFFTAG_IMAGEWIDTH,    WIDTH);
//  TIFFSetField(tif,TIFFTAG_IMAGELENGTH,   HEIGHT);
//  TIFFSetField(tif,TIFFTAG_COMPRESSION,   COMPRESSION_NONE);
//  TIFFSetField(tif,TIFFTAG_PHOTOMETRIC,   PHOTOMETRIC_MINISBLACK);
//  TIFFSetField(tif,TIFFTAG_PLANARCONFIG,  PLANARCONFIG_CONTIG);
//  TIFFSetField(tif,TIFFTAG_BITSPERSAMPLE, 8);
//  TIFFSetField(tif,TIFFTAG_ROWSPERSTRIP,  20L);
//
//  const double tiepoints[6]={0,0,0,130.0,32.0,0.0};
//  const double pixscale[3]={1,1,0};
//  TIFFSetField(tif,TIFFTAG_GEOTIEPOINTS, 6,tiepoints);
//  TIFFSetField(tif,TIFFTAG_GEOPIXELSCALE, 3,pixscale);
//}
//
//void SetUpGeoKeys(GTIF *gtif)
//{
//  GTIFKeySet(gtif, GTModelTypeGeoKey, TYPE_SHORT, 1, ModelGeographic);
//  GTIFKeySet(gtif, GTCitationGeoKey, TYPE_ASCII, 0, "Just An Example");
//  GTIFKeySet(gtif, GeographicTypeGeoKey, TYPE_SHORT,  1, KvUserDefined);
//  GTIFKeySet(gtif, GeogCitationGeoKey, TYPE_ASCII, 0, "Everest Ellipsoid Used.");
//  GTIFKeySet(gtif, GTRasterTypeGeoKey, TYPE_SHORT, 1, RasterPixelIsArea);
//  GTIFKeySet(gtif, GeogAngularUnitsGeoKey, TYPE_SHORT,  1, Angular_Degree);
//  GTIFKeySet(gtif, GeogLinearUnitsGeoKey, TYPE_SHORT,  1, Linear_Meter);
//  GTIFKeySet(gtif, GeogGeodeticDatumGeoKey, TYPE_SHORT,     1, KvUserDefined);
//  GTIFKeySet(gtif, GeogEllipsoidGeoKey, TYPE_SHORT,     1, Ellipse_Everest_1830_1967_Definition);
//  GTIFKeySet(gtif, GeogSemiMajorAxisGeoKey, TYPE_DOUBLE, 1, (double)6377298.556);
//  GTIFKeySet(gtif, GeogInvFlatteningGeoKey, TYPE_DOUBLE, 1, (double)300.8017);
//}
//
//void WriteImage(TIFF *tif)
//{
//  char buffer[WIDTH];
//
//  memset(buffer,0,(size_t)WIDTH);
//  for (int i=0;i<HEIGHT;i++)
//    if (!TIFFWriteScanline(tif, buffer, i, 0))
//      TIFFError("WriteImage","failure in WriteScanline\n");
//}
//
