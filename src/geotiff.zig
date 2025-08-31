//! GeoTIFF API in Zig
const std = @import("std");
const c = @cImport({
    @cInclude("geotiffio.h");
    @cInclude("xtiffio.h");
});

const ArrayList = std.array_list.Managed;
const Allocator = std.mem.Allocator;

const logger = std.log.scoped(.geotiff);

pub const ModelType = enum(u8) {
    /// Projection Coordinate System
    Projected = 1,
    /// Geographic latitude-longitude System
    Geographic = 2,
    /// Geocentric (X,Y,Z) Coordinate System
    Geocentric = 3,
};

pub const SampleFormat = enum(u16) {
    /// unsigned integer data
    Uint = 1,
    /// signed integer data
    Int = 2,
    /// IEEE floating point data
    Float = 3,
    /// untyped data
    Void = 4,
    /// complex signed int
    ComplexInt = 5,
    /// complex ieee floating
    ComplexFloat = 6,
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

pub const RasterType = enum(u16) {
    PixelIsArea = 1,
    PixelIsPoint = 2,
};

pub const GTiffKey = enum(u16) {
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

    // Set the enum to open
    _,
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

/// Data structure defining a TIFF image to be written.
pub const ImageData = struct {
    /// Width of the image (pixels)
    width: u32,
    /// Height of the image (pixels)
    height: u32,
    /// Number of channels of data per pixel (e.g. RGB = 3)
    nchan: u8,
    /// Number of bits of data per channel
    bits_per_chan: u8,
    /// Type of the image
    pixel_format: PixelFormat = .rgb,
    /// Data type of each sample (channel) in each pixel
    sample_format: SampleFormat = .Uint,
    /// The raw pixel data of the image.
    /// It is assumed that the data layout is (sample, column, row).
    pixels: []const u8,
};

/// Handle the return value of a C function call
fn tryCall(res: c_int) !void {
    if (res < 0) {
        return error.CError;
    }
}

/// Struct to create and interact with GeoTIFF files.
pub const GTiff = struct {
    tif: ?*c.TIFF = undefined,
    gtif: *c.GTIF = undefined,
    client_data: ?*TIFFMemWriter = null,

    /// Initialize a new GeoTiff file on disk.
    pub fn init(file: []const u8) !GTiff {
        var gtif = GTiff{};

        // TIFF-level descriptor
        if (c.XTIFFOpen(@ptrCast(file), "w")) |tif| {
            gtif.tif = tif;
        } else {
            return error.TIFFOpenFailed;
        }

        // GeoKey-level descriptor
        if (c.GTIFNew(gtif.tif.?)) |g| {
            gtif.gtif = g;
        } else {
            c.TIFFClose(gtif.tif.?);
            return error.GTIFNewFailed;
        }

        return gtif;
    }

    /// Initialize a new GeoTIFF file for in-memory writing (as opposed to writing to disk).
    /// The file contents may be accessed from the TIFFMemWriter returned when close()-ing the file.
    pub fn initInMemory(alloc: std.mem.Allocator, name: []const u8) !GTiff {
        var gtif = GTiff{};

        // Registers an extension with libtiff for adding GeoTIFF tags.
        // This is noramlly called by the wrapper function XTIFFOpen().
        c.XTIFFInitialize();

        // Allocate the client data structure that libtiff will use via thandle_t.
        // We must heap allocate here, as we're passing a pointer into the TIFF APIs.
        var client_data: ?*TIFFMemWriter = try TIFFMemWriter.create(alloc);
        gtif.client_data = client_data;
        gtif.tif = client_data.?.open(name, "w");
        if (gtif.tif == null) return error.TiffOpenError;

        // GeoKey-level descriptor
        if (c.GTIFNew(gtif.tif.?)) |g| {
            gtif.gtif = g;
        } else {
            c.TIFFClose(gtif.tif.?);
            return error.GTIFNewFailed;
        }

        return gtif;
    }

    /// Close the TIFF file and return the written in-memory file.
    /// The caller owns the returned memory.
    pub fn close(self: *const GTiff) ?*TIFFMemWriter {
        if (self.tif) |tif| {
            c.TIFFClose(tif);
            return self.client_data;
        }
        return null;
    }

    /// Close the TIFF file and free any the in-memory file, if available.
    pub fn deinit(self: *const GTiff) void {
        if (self.tif) |tif| {
            c.TIFFClose(tif);
            if (self.client_data) |data| {
                data.deinit();
                data.allocator.destroy(data);
            }
        }
    }

    /// Set a GTIffKey's value as a u16 (short)
    pub fn SetKeyShort(self: *GTiff, key: GTiffKey, value: u16) !void {
        try tryCall(c.GTIFKeySet(self.gtif, @intFromEnum(key), c.TYPE_SHORT, 1, value));
    }

    /// Set a GTIffKey's value as a double
    pub fn SetKeyDouble(self: *GTiff, key: GTiffKey, value: f64) !void {
        try tryCall(c.GTIFKeySet(self.gtif, @intFromEnum(key), c.TYPE_DOUBLE, 1, value));
    }

    /// Set a GTIffKey's value as an ASCII string
    pub fn SetKeyAscii(self: *GTiff, key: GTiffKey, value: []const u8) !void {
        try tryCall(c.GTIFKeySet(self.gtif, @intFromEnum(key), c.TYPE_ASCII, 0, &value[0]));
    }

    /// Write the image data to the TIFF file.
    /// This additionally sets the width, height, and pixel format metadata.
    /// Note: The file is not actually valid untill TIFFClose() is called.
    pub fn writeImage(self: *GTiff, image: ImageData) !void {
        const stride: u32 = image.width * image.nchan * (image.bits_per_chan / 8);
        const nbytes: u32 = image.height * stride;
        std.debug.assert(image.pixels.len == nbytes);

        // Basic metadata
        try tryCall(c.TIFFSetField(self.tif, c.TIFFTAG_COMPRESSION, c.COMPRESSION_NONE));
        try tryCall(c.TIFFSetField(self.tif, c.TIFFTAG_PLANARCONFIG, c.PLANARCONFIG_CONTIG));

        try self.setPixelFormat(image.pixel_format);
        try self.setSampleFormat(image.sample_format);

        // Image metadata: Width, Height, Number of channels (samples) per pixel, bit size of each channel (sample)
        try tryCall(c.TIFFSetField(self.tif, c.TIFFTAG_IMAGEWIDTH, image.width));
        try tryCall(c.TIFFSetField(self.tif, c.TIFFTAG_IMAGELENGTH, image.height));
        try tryCall(c.TIFFSetField(self.tif, c.TIFFTAG_ROWSPERSTRIP, @as(u16, 1)));
        try tryCall(c.TIFFSetField(self.tif, c.TIFFTAG_SAMPLESPERPIXEL, @as(u16, image.nchan)));
        try tryCall(c.TIFFSetField(self.tif, c.TIFFTAG_BITSPERSAMPLE, @as(u16, image.bits_per_chan)));

        // Basic GeoTIFF tags
        try tryCall(c.GTIFKeySet(self.gtif, c.GTRasterTypeGeoKey, c.TYPE_SHORT, 1, c.RasterPixelIsArea));
        try tryCall(c.GTIFKeySet(self.gtif, c.GeogAngularUnitsGeoKey, c.TYPE_SHORT, 1, c.Angular_Degree));
        try tryCall(c.GTIFKeySet(self.gtif, c.GeogLinearUnitsGeoKey, c.TYPE_SHORT, 1, c.Linear_Meter));

        try tryCall(c.GTIFWriteKeys(self.gtif));

        var i: u32 = 0;
        while (i < image.height) : (i += 1) {
            const line: *anyopaque = @ptrCast(@constCast(&image.pixels[i * stride]));
            try tryCall(c.TIFFWriteScanline(self.tif, line, i, 0));
        }
    }

    /// Get the in-memory TIFF file buffer, if it exists.
    /// Returns the existing slice of memory from the written buffer (owned by the GTiff object).
    pub fn getMemoryBuffer(self: *GTiff) ?[]const u8 {
        if (self.client_data) |data| {
            return data.buffer.items;
        }
        return null;
    }

    /// Set the raster-space to model-space mapping.
    /// Sets the point (pixel) [i,j] of the raster space to the model-space [x,y] position.
    /// We are ignoring multi-valued raster images (K index) and 3D mappings.
    pub fn setOrigin(self: *GTiff, i: usize, j: usize, x: f64, y: f64) !void {
        // [i, j, k, x, y, z]
        const tiepoints: [6]f64 = .{ @floatFromInt(i), @floatFromInt(j), 0, x, y, 0 };
        try tryCall(c.TIFFSetField(self.tif, c.TIFFTAG_GEOTIEPOINTS, @as(u32, 6), &tiepoints[0]));
    }

    /// Set the pixel scale
    pub fn setPixelScale(self: *GTiff, xscale: f64, yscale: f64) !void {
        const pixscale: [3]f64 = .{ xscale, yscale, 0 };
        try tryCall(c.TIFFSetField(self.tif, c.TIFFTAG_GEOPIXELSCALE, @as(u32, 3), &pixscale[0]));
    }

    /// Set the pixel format (type of image - RGB, greyscale, etc.)
    pub fn setPixelFormat(self: *GTiff, format: PixelFormat) !void {
        try tryCall(c.TIFFSetField(self.tif, c.TIFFTAG_PHOTOMETRIC, @intFromEnum(format)));
    }

    /// Set the sample data format
    pub fn setSampleFormat(self: *GTiff, format: SampleFormat) !void {
        try tryCall(c.TIFFSetField(self.tif, c.TIFFTAG_SAMPLEFORMAT, @intFromEnum(format)));
    }
};

// Aliases for libtiff's C types for clarity
const tsize_t = c.tsize_t;
const tmsize_t = c.tmsize_t;
const toff_t = c.toff_t;
const thandle_t = c.thandle_t; // Typically void* or similar opaque handle

/// Structure to hold client data for libtiff callbacks.
/// This includes a pointer to the Zig ArrayList serving as the buffer,
/// the current read/write offset within that buffer, and the allocator
/// that was used to create this TIFFMemWriter instance.
const TIFFMemWriter = struct {
    allocator: std.mem.Allocator,
    buffer: ArrayList(u8),
    current_offset: toff_t = 0,

    pub fn create(alloc: Allocator) !*TIFFMemWriter {
        const writer: *TIFFMemWriter = try alloc.create(TIFFMemWriter);
        writer.allocator = alloc;
        writer.buffer = ArrayList(u8).init(alloc);
        writer.current_offset = 0;
        return writer;
    }

    pub fn deinit(self: *const TIFFMemWriter) void {
        self.buffer.deinit();
        self.allocator.destroy(self);
    }

    /// Opens a TIFF "file" in memory for reading or writing using libtiff.
    ///
    /// @param name: File (stream) name (used by libtiff for errors).
    /// @param mode: File open mode ("r", "w", "rw", etc.)
    ///
    /// Returns a libtiff TIFF file handle.
    pub fn open(client_data: *TIFFMemWriter, name: []const u8, mode: []const u8) ?*c.TIFF {
        return c.TIFFClientOpen(
            @ptrCast(name),
            @ptrCast(mode),
            @ptrCast(client_data), // Pass our client data struct as a thandle_t
            TIFFMemWriter.memRead,
            TIFFMemWriter.memWrite,
            TIFFMemWriter.memSeek,
            TIFFMemWriter.memClose,
            TIFFMemWriter.memSize,
            null, // map_file_proc (mmap not supported for this in-memory version)
            null, // unmap_file_proc
        );
    }

    /// libtiff read callback for in-memory data.
    fn memRead(client_data_handle: thandle_t, user_buf_opaque: ?*anyopaque, read_size_c: tsize_t) callconv(.c) tsize_t {
        const client_data: *TIFFMemWriter = @ptrCast(@alignCast(client_data_handle));

        // Ensure user_buf_opaque is not null if read_size_c > 0, then cast
        var user_buf_ptr: [*]u8 = undefined;
        if (read_size_c > 0 and user_buf_opaque == null) {
            logger.err("memRead: user_buf is null with read_size > 0", .{});
            return @intCast(-1);
        } else if (read_size_c == 0) {
            return 0;
        } else {
            user_buf_ptr = @ptrCast(@alignCast(user_buf_opaque.?));
        }

        const read_size: usize = @intCast(read_size_c); // Assume tsize_t fits in usize for simplicity

        // Check for End-Of-File (EOF)
        if (client_data.current_offset >= @as(toff_t, @intCast(client_data.buffer.items.len))) {
            return 0; // EOF
        }

        // Calculate how many bytes can actually be read
        var bytes_to_read: usize = read_size;
        const buffer_len_toff: toff_t = @intCast(client_data.buffer.items.len);
        const remaining_bytes_in_buffer: toff_t = buffer_len_toff - client_data.current_offset;

        if (@as(toff_t, @intCast(bytes_to_read)) > remaining_bytes_in_buffer) {
            bytes_to_read = @intCast(remaining_bytes_in_buffer);
        }

        if (bytes_to_read == 0) return 0; // Nothing to read (e.g. offset at exact end)

        // Perform the read operation
        const offset_usize: usize = @intCast(client_data.current_offset);
        @memcpy(user_buf_ptr[0..bytes_to_read], client_data.buffer.items[offset_usize .. offset_usize + bytes_to_read]);

        client_data.current_offset += @intCast(bytes_to_read);
        return @intCast(bytes_to_read);
    }

    /// libtiff write callback for in-memory data.
    fn memWrite(client_data_handle: thandle_t, user_buf_opaque: ?*anyopaque, write_size_c: tsize_t) callconv(.c) tsize_t {
        const client_data: *TIFFMemWriter = @ptrCast(@alignCast(client_data_handle));

        var user_buf_ptr: [*]const u8 = undefined;

        if (write_size_c > 0 and user_buf_opaque == null) {
            logger.err("memWrite: user_buf is null with write_size > 0", .{});
            return @intCast(-1);
        } else if (write_size_c == 0) {
            return 0;
        } else {
            user_buf_ptr = @ptrCast(@alignCast(user_buf_opaque.?));
        }

        const write_size: usize = @intCast(write_size_c);

        const current_offset_usize: usize = @intCast(client_data.current_offset);
        const required_end_offset_usize: usize = current_offset_usize + write_size;

        // Ensure the ArrayList buffer has enough capacity and its length is updated.
        // ArrayList.resize() will update items.len.
        if (required_end_offset_usize > client_data.buffer.items.len) {
            client_data.buffer.resize(required_end_offset_usize) catch |err| {
                logger.err("memWrite: Failed to resize buffer: {any}", .{err});
                return @intCast(-1);
            };
        }

        // Perform the write operation
        @memcpy(client_data.buffer.items[current_offset_usize..required_end_offset_usize], user_buf_ptr[0..write_size]);

        client_data.current_offset = @as(toff_t, @intCast(required_end_offset_usize));

        // client_data.buffer.items.len is already updated by resize if the buffer grew.
        // This behavior matches the C version where mem_buffer->size is updated.
        return @intCast(write_size);
    }

    /// libtiff seek callback for in-memory data.
    fn memSeek(client_data_handle: thandle_t, offset_c: toff_t, whence: c_int) callconv(.c) toff_t {
        const client_data: *TIFFMemWriter = @ptrCast(@alignCast(client_data_handle));

        var new_offset: toff_t = undefined;

        switch (whence) {
            c.SEEK_SET => {
                new_offset = offset_c;
            },
            c.SEEK_CUR => {
                // Basic overflow check for toff_t (often i64)
                if ((offset_c > 0 and client_data.current_offset > std.math.maxInt(toff_t) - offset_c) or
                    (offset_c < 0 and client_data.current_offset < std.math.minInt(toff_t) - offset_c))
                {
                    logger.err("memSeek: Seek offset overflow (current + offset)", .{});
                    return std.math.maxInt(toff_t);
                }
                new_offset = client_data.current_offset + offset_c;
            },
            c.SEEK_END => {
                const buffer_len_toff: toff_t = @intCast(client_data.buffer.items.len);
                if ((offset_c > 0 and buffer_len_toff > std.math.maxInt(toff_t) - offset_c) or
                    (offset_c < 0 and buffer_len_toff < std.math.minInt(toff_t) - offset_c))
                {
                    logger.err("memSeek: Seek offset overflow (size + offset)", .{});
                    return std.math.maxInt(toff_t);
                }
                new_offset = buffer_len_toff + offset_c;
            },
            else => {
                logger.err("memSeek: Invalid whence value: {}", .{whence});
                return std.math.maxInt(toff_t);
            },
        }

        if (new_offset < 0) {
            logger.err("memSeek: Attempt to seek to negative offset: {}", .{new_offset});
            return std.math.maxInt(toff_t);
        }

        client_data.current_offset = new_offset;

        // Seeking past the logical end of the buffer is allowed.
        // Subsequent writes via memWrite will extend client_data.buffer.items.len.
        return new_offset;
    }

    /// libtiff close callback for in-memory data.
    /// This function is called by libtiff when TIFFClose() is invoked.
    /// This function does nothing, as we must keep the in-memory buffer alive for access by the client.
    fn memClose(_: thandle_t) callconv(.c) c_int {
        return 0;
    }

    /// libtiff size callback for in-memory data.
    /// Returns the current logical size of the in-memory "file".
    fn memSize(client_data_handle: thandle_t) callconv(.c) toff_t {
        const client_data: *TIFFMemWriter = @ptrCast(@alignCast(client_data_handle));
        return @intCast(client_data.buffer.items.len);
    }
};

test "in-memory TIFF" {
    const allocator = std.testing.allocator;

    const tiff_name: [:0]const u8 = "MemoryTIFF.zig.example";

    var gtif: GTiff = try GTiff.initInMemory(allocator, tiff_name);

    try gtif.SetKeyShort(GTiffKey.GTModelTypeGeoKey, @intFromEnum(ModelType.Projected));
    try gtif.SetKeyShort(GTiffKey.GTRasterTypeGeoKey, @intFromEnum(RasterType.PixelIsArea));
    try gtif.SetKeyShort(GTiffKey.ProjectedCSTypeGeoKey, 3857);
    try gtif.SetKeyAscii(GTiffKey.GTCitationGeoKey, "WGS 84 / Pseudo-Mercator");
    try gtif.SetKeyAscii(GTiffKey.GeogCitationGeoKey, "WGS 84");
    try gtif.SetKeyShort(GTiffKey.GeogAngularUnitsGeoKey, @intFromEnum(UnitType.Angular_Degree));
    try gtif.SetKeyShort(GTiffKey.ProjLinearUnitsGeoKey, @intFromEnum(UnitType.Linear_Meter));

    const width: usize = 64;
    const height: usize = 64;
    const nchan: usize = 3;
    const bytes: usize = width * height * nchan;
    const pixels: [bytes]u8 = [_]u8{0} ** (bytes);

    try gtif.writeImage(.{
        .width = @intCast(width),
        .height = @intCast(height),
        .nchan = @intCast(nchan),
        .pixels = &pixels,
        .pixel_format = .rgb,
        .sample_format = .Uint,
        .bits_per_chan = @intCast(8),
    });

    // Closing the file flushes all pending changes to the in-memory "file"
    const tiff_writer: ?*TIFFMemWriter = gtif.close();
    defer if (tiff_writer) |data| data.deinit();
    if (tiff_writer == null) return error.NoData;

    const data: []const u8 = tiff_writer.?.buffer.items;
    try std.testing.expect(data.len > width * height * nchan);

    // For debugging purposes - Write the file to disk
    // const f = try std.fs.cwd().createFile("test.tif", .{});
    // defer f.close();
    // try f.writeAll(data);
}
