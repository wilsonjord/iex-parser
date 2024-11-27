module pcapng;

enum MagicNumber = 0x1A2B3C4D;

enum BlockType {
    sectionHeader        = 0x0A0D0D0A,
    interfaceDescription = 0x00000001,
    enhancedPacket       = 0x00000006,
}

enum LinkType {
    ethernet = 1 // IEEE 802.3
}

struct SectionHeaderBlock {
    uint length;
    uint bom;
    ushort major;
    ushort minor;
    long sectionLength;
}
