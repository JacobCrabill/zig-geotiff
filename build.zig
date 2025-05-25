const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const linkage = b.option(
        std.builtin.LinkMode,
        "linkage",
        "Specify static or dynamic linkage",
    ) orelse .static;

    // =========================================================================
    // Dependencies

    const zlib_dep = b.dependency("zlib", .{ .target = target, .optimize = optimize });
    const libz = zlib_dep.artifact("z");

    const libtiff_dep = b.dependency("libtiff", .{ .target = target, .optimize = optimize });
    const libtiff = libtiff_dep.artifact("tiff");

    const proj_deb = b.dependency("proj", .{ .target = target, .optimize = optimize });
    const libproj = proj_deb.artifact("proj");

    // The actual source we're building
    const geotiff = b.dependency("geotiff", .{});

    // =========================================================================
    // Compiler Flags

    const std_c_flags: []const []const u8 = &.{
        "--std=c99",
        "-fPIC",
        "-W",
        "-Wall",
        "-Wextra",
        "-Wpedantic",
        "-Wuninitialized",
        "-Wstrict-aliasing",
        "-Wcast-align",
        "-Wconversion",
    };

    // =========================================================================
    // Configured Files

    const gtiff_h = b.addConfigHeader(.{
        .style = .{ .cmake = geotiff.path("libgeotiff/geotiff.h.in") },
        .include_path = "geotiff.h",
    }, .{
        .LIBGEOTIFF_MAJOR_VERSION = 1,
        .LIBGEOTIFF_MINOR_VERSION = 7,
        .LIBGEOTIFF_PATCH_VERSION = 4,
        .LIBGEOTIFF_REV_VERSION = 0,
        .LIBGEOTIFF_VERSION = 1740,
        .LIBGEOTIFF_STRING_VERSION = "1.7.4",
    });

    const geo_config_h = b.addConfigHeader(.{
        .style = .{ .cmake = geotiff.path("libgeotiff/cmake/geo_config.h.in") },
        .include_path = "geo_config.h",
    }, .{
        .GEOTIFF_HAVE_STRINGS_H = 1,
        .GEO_NORMALIZE_DISABLE_TOWGS84 = null,
    });

    // =========================================================================
    // Libraries

    const libgeotiff = b.addLibrary(.{
        .name = "geotiff",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .pic = true,
            .link_libc = true,
            .link_libcpp = true,
        }),
        .linkage = linkage,
    });

    libgeotiff.addConfigHeader(gtiff_h);
    libgeotiff.addConfigHeader(geo_config_h);
    libgeotiff.installConfigHeader(gtiff_h);
    libgeotiff.installConfigHeader(geo_config_h);

    libgeotiff.addIncludePath(geotiff.path("libgeotiff"));
    libgeotiff.addIncludePath(geotiff.path("libgeotiff/libxtiff"));

    // The repo is not well organized, so we can't just use installHeadersDirectory().
    // Instead, install each individual header & include file directly.
    for (geotiff_headers) |h| {
        libgeotiff.installHeader(geotiff.path(b.fmt("libgeotiff/{s}", .{h})), h);
    }
    libgeotiff.installHeader(geotiff.path("libgeotiff/libxtiff/xtiffio.h"), "xtiffio.h");

    libgeotiff.linkLibrary(libz);
    libgeotiff.linkLibrary(libtiff);
    libgeotiff.linkLibrary(libproj);

    libgeotiff.installLibraryHeaders(libtiff);
    libgeotiff.installLibraryHeaders(libproj);

    libgeotiff.addCSourceFiles(.{
        .root = geotiff.path("libgeotiff"),
        .files = geotiff_lib_sources,
        .flags = std_c_flags,
    });

    b.installArtifact(libgeotiff);

    // =========================================================================
    // Executables

    const example = b.addExecutable(.{
        .name = "makegeo",
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    example.addCSourceFile(.{
        .file = geotiff.path("libgeotiff/bin/makegeo.c"),
        .flags = std_c_flags,
    });
    example.linkLibrary(libgeotiff);

    b.installArtifact(example);

    // =========================================================================
    // Zig Module
    const mod = b.addModule("geotiff", .{
        .root_source_file = b.path("src/geotiff.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    mod.linkLibrary(libgeotiff);

    const example2 = b.addExecutable(.{
        .name = "example",
        .root_source_file = b.path("src/example.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    example2.root_module.addImport("geotiff", mod);

    b.installArtifact(example2);
}

const geotiff_lib_sources: []const []const u8 = &.{
    "cpl_serv.c",
    "geo_extra.c",
    "geo_free.c",
    "geo_get.c",
    "geo_names.c",
    "geo_new.c",
    "geo_normalize.c",
    "geo_print.c",
    "geo_set.c",
    "geo_simpletags.c",
    "geo_tiffp.c",
    "geo_trans.c",
    "geo_write.c",
    "geotiff_proj4.c",
    "libxtiff/xtiff.c",
};

const geotiff_headers: []const []const u8 = &.{
    "cpl_serv.h",
    "epsg_datum.inc",
    "epsg_ellipse.inc",
    "epsg_gcs.inc",
    "epsg_pcs.inc",
    "epsg_pm.inc",
    "epsg_proj.inc",
    "epsg_units.inc",
    "epsg_vertcs.inc",
    "geo_ctrans.inc",
    "geo_keyp.h",
    "geo_normalize.h",
    "geo_simpletags.h",
    "geo_tiffp.h",
    "geokeys.h",
    "geokeys.inc",
    "geokeys_v1_1.inc",
    "geonames.h",
    "geotiff.h.in",
    "geotiffio.h",
    "geovalues.h",
};
