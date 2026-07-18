module pcap;

// file magic, as read in the file's native byte order
enum MagicNumber : uint {
    microseconds        = 0xa1b2c3d4,
    nanoseconds         = 0xa1b23c4d,
    microsecondsSwapped = 0xd4c3b2a1,
    nanosecondsSwapped  = 0x4d3cb2a1,
}
