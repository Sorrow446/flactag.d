# flactag.d
Pure D library for reading and writing FLAC tags.    
It is stable and fairly optimised, but it could do with a little clean-up.

## Set-up
```d
import flactag.flactag : FlacTag;
import flactag.objects : FlacTags, FlacPicture, FlacPictureType;

FlacTag flac = new FlacTag(`G:\track.flac`);
```
Opening a FLAC file.

## Examples
### Reading tags
```d
FlacTags tags = flac.readTags();
string album = tags.getFirst("ALBUM");
string title = tags.getFirst("TITLE");

// FLAC allows multiple of the same field names.
string[] comments = tags.getAll("COMMENT");
```

### Writing tags
```d
FlacTags tags;
tags.set("ALBUM", "my album");
tags.setMany("COMMENT", ["com one", "com two"]);

```

### Extracting pics
```d
FlacPicture[] pics = tags.getAllPictures();
foreach (idx, pic; pics)
{
	auto fname = format("%02d.jpg", idx + 1);
 	pic.writeToFile(fname);
}
```

### Writing a pic
```d
FlacTags tags;
auto coverData = cast(ubyte[]) read("cover.jpg");

auto pic = FlacPicture(
	mimeType: "image/jpeg",
	type: FlacPictureType.FrontCover,
	data: coverData,
	description: "my desc"
);

tags.addPicture(pic);
flac.writeTags(tags);
```

## Disclaimer
flactag.d is stable, but you should still back up your tracks just in case.
