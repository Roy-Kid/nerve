import { strict as assert } from "node:assert";
import {
  isAbsolutePath,
  isInside,
  pathFromFileUri,
  pathStyle,
} from "../../src/model/path";

suite("wire paths", () => {
  test("a leading slash is posix", () => {
    assert.equal(pathStyle("/Users/me/proj"), "posix");
  });

  test("a drive with either slash is windows", () => {
    assert.equal(pathStyle("C:\\work\\nerve"), "windows");
    assert.equal(pathStyle("c:/work/nerve"), "windows");
  });

  test("a unc share is windows", () => {
    assert.equal(pathStyle("\\\\srv\\share\\proj"), "windows");
  });

  test("a drive-relative path is not absolute", () => {
    // `C:work` names a directory relative to the current one on drive C.
    assert.equal(pathStyle("C:work"), undefined);
    assert.equal(isAbsolutePath("C:work"), false);
  });

  test("relative paths are not absolute", () => {
    for (const path of ["proj", "~/proj", "./proj", ""]) {
      assert.equal(isAbsolutePath(path), false, path);
    }
  });
});

suite("folder containment", () => {
  test("posix paths compare exactly", () => {
    assert.equal(isInside("/Users/me/proj", "/Users/me"), true);
    assert.equal(isInside("/Users/me", "/Users/me"), true);
    assert.equal(isInside("/Users/other", "/Users/me"), false);
  });

  test("a trailing slash on either side is ignored", () => {
    assert.equal(isInside("/Users/me/proj/", "/Users/me/"), true);
  });

  test("a sibling with a shared prefix is not inside", () => {
    assert.equal(isInside("/Users/mexican", "/Users/me"), false);
  });

  test("windows separators are interchangeable", () => {
    // The folder filter was dead on Windows: `C:\Users\me\proj` never matched
    // `C:\Users\me`, because the comparison only knew about `/`.
    assert.equal(isInside("C:\\Users\\me\\proj", "C:\\Users\\me"), true);
    assert.equal(isInside("C:/Users/me/proj", "C:\\Users\\me"), true);
  });

  test("windows comparison ignores case", () => {
    assert.equal(isInside("C:\\Users\\Me\\Proj", "c:\\users\\me"), true);
  });

  test("posix comparison does not ignore case", () => {
    assert.equal(isInside("/Users/Me/proj", "/users/me"), false);
  });
});

suite("file uris", () => {
  test("a posix uri decodes", () => {
    assert.equal(pathFromFileUri("file:///Users/me/proj"), "/Users/me/proj");
  });

  test("percent escapes decode", () => {
    assert.equal(
      pathFromFileUri("file:///Users/me/proj%20foo"),
      "/Users/me/proj foo",
    );
    assert.equal(
      pathFromFileUri("file:///Users/me/%E9%A1%B9%E7%9B%AE"),
      "/Users/me/项目",
    );
  });

  test("a bad escape degrades instead of throwing", () => {
    assert.equal(pathFromFileUri("file:///tmp/100%/done"), "/tmp/100%/done");
  });

  test("a drive survives every slash count and an escaped colon", () => {
    // `file:///C:/x` used to decode to `/C:/x` — a path that exists nowhere.
    for (const uri of [
      "file:///C:/work",
      "file://C:/work",
      "file:///C%3A/work",
    ]) {
      assert.equal(pathFromFileUri(uri), "C:/work", uri);
    }
  });

  test("the localhost authority is accepted", () => {
    assert.equal(
      pathFromFileUri("file://localhost/Users/me/proj"),
      "/Users/me/proj",
    );
  });

  test("a unc server round-trips to backslashes", () => {
    assert.equal(pathFromFileUri("file://srv/share/proj"), "\\\\srv\\share\\proj");
  });

  test("a non-file url is not a path", () => {
    assert.equal(pathFromFileUri("vscode://file/Users/me"), undefined);
  });
});
