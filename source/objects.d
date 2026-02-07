module flactag.objects;

import std.file;
import std.string;

struct Blocks
{
    Block[] streamBlocks;
    Block[] picBlocks;
    Block[] otherBlocks;
}

struct Block
{
    ubyte type;
    ubyte[] data;
}

enum FlacPictureType : uint
{
    Other = 0,
    Icon,
    OtherIcon,
    FrontCover,
    BackCover,
    Leaflet,
    Media,
    LeadArtist,
    Artist,
    Conductor,
    Band,
    Composer,
    Lyricist,
    RecordingLocation,
    DuringRecording,
    DuringPerformance,
    VideoCapture,
    Illustration,
    BandLogotype,
    PublisherLogotype
}

class InvalidMagicException : Exception
{
    this(string msg) { super(msg); }
}

class IncorrectFirstBlockException : Exception
{
    this(string msg) { super(msg); }
}

class MetadataBlockTooLarge : Exception
{
    this(string msg) { super(msg); }
}

struct FlacPicture
{
    string description;
    string mimeType;
    ubyte[] data;
    int width;
    int height;
    int depth;
    int coloursNum;
    FlacPictureType type;

    void writeToFile(string outPath) {
      if (data.length > 0)
      {
        write(outPath, data);
      }
    }
}


struct FlacTags
{
    package string vendor;
    package string[][string] tagMap;
    package FlacPicture[] pictures;
    package string[] setFields;

    string getFirst(string key)
    {
        auto k = key.toUpper();

        if (auto p = k in tagMap) { 
            return (*p)[0];
        }
        return "";
    }

    FlacPicture getFirstPicture()
    {
        return pictures.length > 0 ? pictures[0] : FlacPicture();
    }

    bool hasNthPicture(size_t idx) {
        return idx < pictures.length;
    }

    FlacPicture getNthPicture(size_t idx)
    {
        return hasNthPicture(idx) ? pictures[idx] : FlacPicture();
    }

    string[] getAll(string key)
    {
        auto k = key.toUpper();

        if (k in tagMap) {
            return tagMap[k];
        }
        return [];
    }

    FlacPicture[] getAllPictures()
    {
        return pictures;
    }

    string[] getFieldNames()
    {
        return tagMap.keys;
    }

    bool hasTag(string key)
    {
        auto k = key.toUpper();
        return (k in tagMap) !is null;
    }

    bool hasPictures()
    {
        return pictures.length > 0;
    }

    void set(string key, string value) {
        auto k = key.toUpper();

        tagMap[k] = [value];
        setFields ~= k;
    }

    void setMany(string key, string[] values) {
        auto k = key.toUpper();

        tagMap[k] = values.dup;
        setFields ~= k;
    }

    void add(string key, string value) {
        auto k = key.toUpper();

        tagMap[k] ~= value;
    }

    void addMany(string key, string[] value) {
        auto k = key.toUpper();

        tagMap[k] ~= value.dup;
    }

    void addPicture(ref FlacPicture pic) {
        pictures ~= pic;
    }    

    void setPicture(ref FlacPicture pic) {
        pictures = [pic];
        setFields ~= "__PICS__";
    }

    void remove(string key) {
        auto k = key.toUpper();

        if (k in tagMap) {
          tagMap.remove(k);
        }
    }

    void removeAll() {
      tagMap = string[][string].init;
    }   

    void removeAllPictures() {
        pictures = [];
    }

    string getVendor() {
      return vendor;
    }

    void setVendor(string v) {
      if (vendor.length > 0) { vendor = v; }
    }
}