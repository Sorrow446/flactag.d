module flactag.flactag;

import std.stdio;
import std.path;
import std.exception;
import std.array;
import std.string;
import std.datetime : Clock;
import std.format : format;
import std.file;
import std.range;
import std.algorithm;

import flactag.objects;

class FlacTag
{
    private File f;

    this(string path)
    {
        f = File(path, "rb");
        checkHeader();
    }

    ~this()
    {
        f.close();
    }

    private void skipBlock()
    {
        uint size = readBeU24();
        f.seek(size, SEEK_CUR);
    }

    FlacTags readTags()
    {
        FlacTags tags;

        f.seek(4, SEEK_SET);

        ubyte[] buf = [0];

        while (true)
        {
            if (f.rawRead(buf).length < 1) { break; }

            ubyte b = buf[0];
            ubyte blockType = b & 0x7F;
            bool last = ((b >> 7) & 1) == 1;

            switch (blockType)
            {
                case 0x4:
                    parseVorbBlock(tags);
                    break;
                case 0x6:
                    parsePicBlock(tags);
                    break;
                default:
                    skipBlock();
                    break;
            }

            if (last) { break; }
        }

        return tags;
    }

    private void readFully(ubyte[] buf)
    {
        size_t total = 0;
        while (total < buf.length)
        {
            ubyte[] slice = f.rawRead(buf[total .. $]);
            enforce(slice.length > 0, "unexpected eof");
            total += slice.length;
        }
    }

    private uint readBeU24()
    {
        ubyte[3] buf;
        readFully(buf[]);

        return buf[0] << 16
            |  buf[1] << 8
            |  buf[2];
    }

    private uint readLeU32()
    {
        ubyte[4] buf;
        readFully(buf[]);
        
        return buf[0]
            |  buf[1] << 8
            |  buf[2] << 16
            |  buf[3] << 24;
    }

    
    private uint readBeU32()
    {
        ubyte[4] buf;
        readFully(buf[]);

        return (cast(uint)buf[0] << 24)
            | (cast(uint)buf[1] << 16)
            | (cast(uint)buf[2] << 8)
            | (cast(uint)buf[3]);
    }

    private void toLeU32(ref ubyte[4] buf, uint value)
    {
        buf[0] = cast(ubyte)value;
        buf[1] = cast(ubyte)(value >> 8);
        buf[2] = cast(ubyte)(value >> 16);
        buf[3] = cast(ubyte)(value >> 24);
    }

    private void toBeU24(ref ubyte[3] buf, uint value)
    {
        buf[0] = cast(ubyte)(value >> 16);
        buf[1] = cast(ubyte)(value >> 8);
        buf[2] = cast(ubyte)value;
    }

    private void toBeU32(ref ubyte[4] buf, uint value)
    {
        buf[0] = cast(ubyte)(value >> 24);
        buf[1] = cast(ubyte)(value >> 16);
        buf[2] = cast(ubyte)(value >> 8);
        buf[3] = cast(ubyte)value;
    }

    private string readString(uint len)
    {
        auto buf = new ubyte[len];
        readFully(buf[]);
        return cast(string) buf;
    }

    private string[] splitComment(string s)
    {
        auto idx = s.indexOf('=');
        if (idx < 0) { return [s]; }

        return [s[0 .. idx], s[idx + 1 .. $]];
    }

    private FlacPictureType picTypeFromUint(uint v)
    {
        if (v < 0 || v > 19) {
          return FlacPictureType.Other;
        }

        return cast(FlacPictureType)cast(uint)v;
    }

    private void parsePicBlock(ref FlacTags tags)
    {
        auto pic = FlacPicture();
        f.seek(3, SEEK_CUR);
        
        uint picType = readBeU32();

        uint mimeLen = readBeU32();
        enforce(mimeLen > 0, "invalid picture mime length");
        ubyte[] mimeBuf = new ubyte[mimeLen];
        enforce(
            f.rawRead(mimeBuf[]).length == mimeLen, "eof reading picture mime"
        );
        pic.mimeType = cast(string)mimeBuf[];

        uint descLen = readBeU32();
        if (descLen > 0)
        {
            ubyte[] descBuf = new ubyte[descLen];
            enforce(
              f.rawRead(descBuf[]).length == descLen, "eof reading picture description"
            );
            pic.description = cast(string)descBuf[];
        }

        pic.width      = cast(int)readBeU32();
        pic.height     = cast(int)readBeU32();
        pic.depth      = cast(int)readBeU32();
        pic.coloursNum = cast(int)readBeU32();

        uint dataLen = readBeU32();
        pic.data = new ubyte[dataLen];
        enforce(
            f.rawRead(pic.data[]).length == dataLen, "eof reading picture data"
        );
          
        pic.type = picTypeFromUint(picType);

        tags.pictures ~= pic;
    }

    private void parseVorbBlock(ref FlacTags tags)
    {
      f.seek(3, SEEK_CUR);

      uint vendorLen = readLeU32();
      if (vendorLen > 0)
      {
          string vendor = readString(vendorLen);
          tags.vendor = vendor;
      }

      uint commentCount = readLeU32();

      foreach (_; 0 .. commentCount)
      {
          uint comLen = readLeU32();
          string comment = readString(comLen);

          auto parts = splitComment(comment);

          enforce(parts.length > 1, "vorbis comment must have at least one '='");

          string field = parts[0].toUpper();
          string value = parts[1];

          tags.tagMap[field] ~= value;
      }
    }

    private void checkHeader()
    {
      ubyte[4] magicBuf;
      enforce(f.rawRead(magicBuf[]).length == 4,
          new Exception("unexpected eof trying to read magic"));

      string magic = cast(string)magicBuf[];
      if (magic != "fLaC")
      {
          throw new InvalidMagicException(
            "file header is corrupted or not a flac file"
          );
      }

      ubyte b;
      enforce(f.rawRead([b]).length == 1,
          new Exception("unexpected eof"));

      ubyte blockType = b & 0x7F;
      if (blockType != 0x00)
      {
        throw new IncorrectFirstBlockException(
          "first block must be streaminfo"
        );
      }

      f.seek(-1, SEEK_CUR);
    }

    private ubyte[] readBlock()
    {
        uint size = readBeU24();

        f.seek(-3, SEEK_CUR);

        auto buf = new ubyte[size + 3];
        readFully(buf[]);
        return buf;
    }


    private string genTempPath()
    {
      string fname = baseName(f.name);
      auto stamp = Clock.currTime().stdTime;

      return buildPath(
          tempDir(),
          format("%s_tmp_%s.flac", fname, stamp)
      );
    }

    private void overwriteTags(ref FlacTags tags, ref FlacTags toWrite)
    {
        foreach (k, v; toWrite.tagMap)
        {
            if (v.length > 0)
            {
              if (canFind(toWrite.setFields, k))
              {
                tags.tagMap[k] = v.dup;
              }
              else
              {
                tags.tagMap[k] ~= v.dup;
              }         
            }
        }

        if (canFind(toWrite.setFields, "__PICS__"))
        {
          tags.pictures = [];
        }

        foreach (p; toWrite.pictures)
        {
          if (p.data.length > 0) {
            tags.pictures ~= p;
          }
        }

    }

    private size_t writeComment(File f, string fieldName, string fieldVal)
    {
        auto pair = fieldName.toUpper() ~ "=" ~ fieldVal;

        auto pairBytes = cast(ubyte[]) pair.idup;
        auto pairLen = cast(uint) pairBytes.length;

        ubyte[4] pairLenLeU32;
        toLeU32(pairLenLeU32, pairLen);
        f.rawWrite(pairLenLeU32);

        f.rawWrite(pairBytes);

        return 4 + pairLen;
    }


    private void writeEnd(File out_f)
    {
        enum size_t bufSize = 4 * 1024 * 1024;
        auto buf = new ubyte[bufSize];

        ubyte[] data;
        while ((data = f.rawRead(buf[])).length > 0) {
          out_f.rawWrite(data);
        }
    }

    private void updateOffsets(ref File out_f, size_t vorbStart, size_t comCountPos, uint comCount, uint written)
    {
        ubyte[4] buf;
        ubyte[3] bufThree;

        toLeU32(buf, comCount);
        out_f.seek(comCountPos, SEEK_SET);
        out_f.rawWrite(buf);

        toBeU24(bufThree, written);
        out_f.seek(vorbStart, SEEK_SET);
        out_f.rawWrite(bufThree);
    }

    private void writePicBlock(ref File out_f, ref FlacPicture cover)
    {
        size_t written = 0;

        auto picDataSize = cast(uint)cover.data.length;
        auto descSize    = cast(uint)cover.description.length;
        auto mimeSize    = cast(uint)cover.mimeType.length;

        out_f.rawWrite(cast(ubyte[])[0x06]);

        auto blockSizePos = out_f.tell();

        out_f.rawWrite(cast(ubyte[])[0x0, 0x0, 0x0]);

        ubyte[4] buf;
        ubyte[3] bufThree;

        toBeU32(buf, cast(uint)cover.type);
        out_f.rawWrite(buf);

        toBeU32(buf, mimeSize);
        out_f.rawWrite(buf);

        out_f.rawWrite(cast(ubyte[])cover.mimeType);

        toBeU32(buf, descSize);
        out_f.rawWrite(buf);

        written += mimeSize + 12;

        if (descSize > 0)
        {
            out_f.rawWrite(cast(ubyte[])cover.description);
            written += descSize;
        }

        toBeU32(buf, cover.width);
        out_f.rawWrite(buf);

        toBeU32(buf, cover.height);
        out_f.rawWrite(buf);

        toBeU32(buf, cover.depth);
        out_f.rawWrite(buf);

        toBeU32(buf, cover.coloursNum);
        out_f.rawWrite(buf);      

        toBeU32(buf, picDataSize);
        out_f.rawWrite(buf); 

        written += 20;

        out_f.rawWrite(cover.data);
        written += picDataSize;

        if (written > 0xFFFFFF) {
          throw new MetadataBlockTooLarge(
            "picture block exceeds the flac metadata block limit"
          );
        }

        auto endBlockPos = out_f.tell();

        out_f.seek(blockSizePos, SEEK_SET);

        toBeU24(bufThree, cast(uint)written);
        out_f.rawWrite(bufThree); 

        out_f.seek(endBlockPos, SEEK_SET);
    }

    private void create(string tempPath, Blocks parsedBlocks, FlacTags toWrite)
    {
      size_t written = 0;
      uint   comCount = 0;
      ulong  endDataStart = f.tell();

      auto tags = readTags();

      overwriteTags(tags, toWrite);

      auto out_f = File(tempPath, "wb+");
      scope(exit) out_f.close();

      out_f.rawWrite(cast(ubyte[])"fLaC");

      auto streamBlock = parsedBlocks.streamBlocks[0];
      out_f.rawWrite(cast(ubyte[])[0x0]);
      out_f.rawWrite(streamBlock.data);

      out_f.rawWrite(cast(ubyte[])[0x4]);
      auto vorbStart = out_f.tell();
      out_f.rawWrite(cast(ubyte[])[0x0, 0x0, 0x0]);

      uint vendorSize = cast(uint)tags.vendor.length;
      ubyte[4] vendorSizeBuf;
      
      toLeU32(vendorSizeBuf, vendorSize);
      out_f.rawWrite(vendorSizeBuf);
      written += 4;

      out_f.rawWrite(cast(ubyte[])tags.vendor);
      written += vendorSize;

      auto comCountPos = out_f.tell();
      out_f.rawWrite(cast(ubyte[])[0x0, 0x0, 0x0, 0x0]);
      written += 4;

      foreach (fieldName, values; tags.tagMap)
      {
          foreach (val; values)
          {
              written += writeComment(out_f, fieldName, val);
              comCount ++;
          }
      }

      if (written > 0xFFFFFF) {
        throw new MetadataBlockTooLarge(
          "vorbis block exceeds the flac metadata block limit"
        );
      }

      foreach (pictureBlock; tags.pictures)
      {
          writePicBlock(out_f, pictureBlock);
      }

      auto lastIdx = parsedBlocks.otherBlocks.length - 1;

      foreach (idx, block; parsedBlocks.otherBlocks.enumerate)
      {
          ubyte b = block.type & 0x7F;

          if (idx == lastIdx) { b |= 0x80; };
              
          out_f.rawWrite([b]);
          out_f.rawWrite(block.data);
      }

      f.seek(endDataStart, SEEK_SET);
      writeEnd(out_f);

      updateOffsets(out_f, vorbStart, comCountPos, cast(uint)comCount, cast(uint)written);
    }

    private void replaceFlac(string tempPath, string flacPath)
    {
        remove(flacPath);
        copy(tempPath, flacPath);
        remove(tempPath);
        
        f = File(flacPath, "rb");
    }

    void writeTags(FlacTags toWrite)
    {
      f.seek(4, SEEK_SET);

      Blocks parsedBlocks;

      ubyte[] buf = [0];

      while (true)
      {
          if (f.rawRead(buf).length < 1) { break; }

          ubyte b = buf[0];
          ubyte blockType = b & 0x7F;
          auto last = ((b >> 7) & 1) == 1;

          auto blockData = readBlock();

          auto block = Block(
              type: blockType,
              data: blockData,
          );

          switch (blockType)
          {
              case 0x0:
                  parsedBlocks.streamBlocks ~= block;
                  break;
              case 0x4:
                  break;  
              case 0x6:
                  parsedBlocks.picBlocks ~= block;
                  break;            
              default:
                  parsedBlocks.otherBlocks ~= block;
                  break;
          };

          if (last) { break; }
      }

      string tempPath = genTempPath();
      create(tempPath, parsedBlocks, toWrite);

      auto destflacPath = absolutePath(f.name);
      f.close();

      replaceFlac(tempPath, destflacPath);

    }
  }