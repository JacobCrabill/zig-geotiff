const std = @import("std");
const c = @cImport({
    @cInclude("geotiffio.h");
    @cInclude("xtiffio.h");
});

pub const ModelType = enum(u8) {
    /// Projection Coordinate System
    Projected = 1,
    /// Geographic latitude-longitude System
    Geographic = 2,
    /// Geocentric (X,Y,Z) Coordinate System
    Geocentric = 3,
};

/// How the data for each pixel should be interpreted.
/// Values taken from tiffio.h.
pub const PixelFormat = enum(u16) {
    /// Greyscale with 0=white, 2**N-1 = black
    greyscale_inverted = 0,
    /// Greyscale with 0=black, 2**N-1 = white
    greyscale = 1,
    /// Red/Green/Blue channels
    rgb = 2,
    /// Color map indexed
    pallete = 3,
    /// $holdout mask
    mask = 4,
    /// !color separations
    separated = 5,
    /// !CCIR 601
    ycbcr = 6,
    /// !1976 CIE L*a*b*
    cielab = 8,
    /// ICC L*a*b* [Adobe TIFF Technote 4]
    icclab = 9,
    /// ITU L*a*b*
    itulab = 10,
    /// color filter array
    cfa = 32803,
    /// CIE Log2(L)
    logl = 32844,
    /// CIE Log2(L) (u',v')
    logluv = 32845,
    _,
};

pub const ImageData = struct {
    width: u32,
    height: u32,
    nchan: u8,
    pixels: []const u8,
    format: PixelFormat = .rgb,
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
        try tryCall(c.GTIFKeySet(self.gtif, key, c.TYPE_ASCII, 0, &value[0]));
    }

    /// Write the image data to the TIFF file.
    /// This additionally sets the width, height, and pixel format metadata.
    pub fn writeImage(self: *GTiff, image: ImageData) !void {
        const nbytes: u32 = image.nchan * image.width * image.height;
        std.debug.assert(image.pixels.len == nbytes);

        // Basic metadata
        try tryCall(c.TIFFSetField(self.tif, c.TIFFTAG_COMPRESSION, c.COMPRESSION_NONE));
        try tryCall(c.TIFFSetField(self.tif, c.TIFFTAG_PLANARCONFIG, c.PLANARCONFIG_CONTIG));
        try tryCall(c.TIFFSetField(self.tif, c.TIFFTAG_PHOTOMETRIC, c.PHOTOMETRIC_RGB));

        // Image metadata: Width, Height, Number of channels (samples) per pixel, bit size of each channel (sample)
        try tryCall(c.TIFFSetField(self.tif, c.TIFFTAG_IMAGEWIDTH, image.width));
        try tryCall(c.TIFFSetField(self.tif, c.TIFFTAG_IMAGELENGTH, image.height));
        try tryCall(c.TIFFSetField(self.tif, c.TIFFTAG_ROWSPERSTRIP, @as(u16, 1)));
        try tryCall(c.TIFFSetField(self.tif, c.TIFFTAG_SAMPLESPERPIXEL, @as(u16, image.nchan)));
        try tryCall(c.TIFFSetField(self.tif, c.TIFFTAG_BITSPERSAMPLE, @as(u16, 8)));

        // Basic GeoTIFF tags
        try tryCall(c.GTIFKeySet(self.gtif, c.GTRasterTypeGeoKey, c.TYPE_SHORT, 1, c.RasterPixelIsArea));
        try tryCall(c.GTIFKeySet(self.gtif, c.GeogAngularUnitsGeoKey, c.TYPE_SHORT, 1, c.Angular_Degree));
        try tryCall(c.GTIFKeySet(self.gtif, c.GeogLinearUnitsGeoKey, c.TYPE_SHORT, 1, c.Linear_Meter));

        const stride: u32 = image.width * image.nchan;
        var i: u32 = 0;
        while (i < image.height) : (i += 1) {
            const line: *anyopaque = @ptrCast(@constCast(&image.pixels[i * stride]));
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
//  TIFF *tif=XTIFFOpen(fname,"w");  /// TIFF-level descriptor
//  if (!tif) {
//    printf("failure in makegeo\n");
//    return -1;
//  }
//
//  GTIF *gtif = GTIFNew(tif);  /// GeoKey-level descriptor
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

pub const RasterType = enum(u16) {
    PixelIsArea = 1,
    PixelIsPoint = 2,
};

pub const GTiffKeys = enum(u16) {
    /// Section 6.3.1.1 Codes
    GTModelTypeGeoKey = 1024,
    /// Section 6.3.1.2 Codes
    GTRasterTypeGeoKey = 1025,
    /// documentation
    GTCitationGeoKey = 1026,

    // 6.2.2 Geographic CS Parameter Keys

    /// Section 6.3.2.1 Codes
    GeographicTypeGeoKey = 2048,
    /// documentation
    GeogCitationGeoKey = 2049,
    /// Section 6.3.2.2 Codes
    GeogGeodeticDatumGeoKey = 2050,
    /// Section 6.3.2.4 codes
    GeogPrimeMeridianGeoKey = 2051,
    /// Section 6.3.1.3 Codes
    GeogLinearUnitsGeoKey = 2052,
    /// meters
    GeogLinearUnitSizeGeoKey = 2053,
    /// Section 6.3.1.4 Codes
    GeogAngularUnitsGeoKey = 2054,
    /// radians
    GeogAngularUnitSizeGeoKey = 2055,
    /// Section 6.3.2.3 Codes
    GeogEllipsoidGeoKey = 2056,
    /// GeogLinearUnits
    GeogSemiMajorAxisGeoKey = 2057,
    /// GeogLinearUnits
    GeogSemiMinorAxisGeoKey = 2058,
    /// ratio
    GeogInvFlatteningGeoKey = 2059,
    /// Section 6.3.1.4 Codes
    GeogAzimuthUnitsGeoKey = 2060,
    /// GeoAngularUnit
    GeogPrimeMeridianLongGeoKey = 2061,
    /// 2011 - proposed addition
    GeogTOWGS84GeoKey = 2062,

    // 6.2.3 Projected CS Parameter Keys
    //    Several keys have been renamed,*/
    //    and the deprecated names aliased for backward compatibility

    /// Section 6.3.3.1 codes
    ProjectedCSTypeGeoKey = 3072,
    /// documentation
    PCSCitationGeoKey = 3073,
    /// Section 6.3.3.2 codes
    ProjectionGeoKey = 3074,
    /// Section 6.3.3.3 codes
    ProjCoordTransGeoKey = 3075,
    /// Section 6.3.1.3 codes
    ProjLinearUnitsGeoKey = 3076,
    /// meters
    ProjLinearUnitSizeGeoKey = 3077,
    /// GeogAngularUnit
    ProjStdParallel1GeoKey = 3078,
    /// ** alias **
    //ProjStdParallelGeoKey=rojStdParallel1GeoKey,
    /// GeogAngularUnit
    ProjStdParallel2GeoKey = 3079,
    /// GeogAngularUnit
    ProjNatOriginLongGeoKey = 3080,
    /// ** alias **
    //ProjOriginLongGeoKey=rojNatOriginLongGeoKey,
    /// GeogAngularUnit
    ProjNatOriginLatGeoKey = 3081,
    /// ** alias **
    //ProjOriginLatGeoKey=rojNatOriginLatGeoKey,
    /// ProjLinearUnits
    ProjFalseEastingGeoKey = 3082,
    /// ProjLinearUnits
    ProjFalseNorthingGeoKey = 3083,
    /// GeogAngularUnit
    ProjFalseOriginLongGeoKey = 3084,
    /// GeogAngularUnit
    ProjFalseOriginLatGeoKey = 3085,
    /// ProjLinearUnits
    ProjFalseOriginEastingGeoKey = 3086,
    /// ProjLinearUnits
    ProjFalseOriginNorthingGeoKey = 3087,
    /// GeogAngularUnit
    ProjCenterLongGeoKey = 3088,
    /// GeogAngularUnit
    ProjCenterLatGeoKey = 3089,
    /// ProjLinearUnits
    ProjCenterEastingGeoKey = 3090,
    /// ProjLinearUnits
    ProjCenterNorthingGeoKey = 3091,
    /// ratio
    ProjScaleAtNatOriginGeoKey = 3092,
    /// ** alias **
    //ProjScaleAtOriginGeoKey=rojScaleAtNatOriginGeoKey,
    /// ratio
    ProjScaleAtCenterGeoKey = 3093,
    /// GeogAzimuthUnit
    ProjAzimuthAngleGeoKey = 3094,
    /// GeogAngularUnit
    ProjStraightVertPoleLongGeoKey = 3095,
    /// GeogAngularUnit
    ProjRectifiedGridAngleGeoKey = 3096,

    /// Section 6.3.4.1 codes
    VerticalCSTypeGeoKey = 4096,
    /// documentation
    VerticalCitationGeoKey = 4097,
    /// Section 6.3.4.2 codes
    VerticalDatumGeoKey = 4098,
    /// Section 6.3.1 (.x) codes
    VerticalUnitsGeoKey = 4099,
};

/// GeoTIFF unit types for LinearUnits AngularUnits keys
pub const UnitType = enum(u16) {
    // -- Linear Types --
    Linear_Meter = 9001,
    Linear_Foot = 9002,
    Linear_Foot_US_Survey = 9003,
    Linear_Foot_Modified_American = 9004,
    Linear_Foot_Clarke = 9005,
    Linear_Foot_Indian = 9006,
    Linear_Link = 9007,
    Linear_Link_Benoit = 9008,
    Linear_Link_Sears = 9009,
    Linear_Chain_Benoit = 9010,
    Linear_Chain_Sears = 9011,
    Linear_Yard_Sears = 9012,
    Linear_Yard_Indian = 9013,
    Linear_Fathom = 9014,
    Linear_Mile_International_Nautical = 9015,

    // -- Angular Units --
    Angular_Radian = 9101,
    Angular_Degree = 9102,
    Angular_Arc_Minute = 9103,
    Angular_Arc_Second = 9104,
    Angular_Grad = 9105,
    Angular_Gon = 9106,
    Angular_DMS = 9107,
    Angular_DMS_Hemisphere = 9108,
};
