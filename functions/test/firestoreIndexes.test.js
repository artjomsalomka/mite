const assert = require("node:assert/strict");
const test = require("node:test");

const indexes = require("../../firestore.indexes.json").indexes;

function hasIndex(collectionGroup, fields) {
  return indexes.some((index) =>
    index.collectionGroup === collectionGroup
    && JSON.stringify(index.fields) === JSON.stringify(fields)
  );
}

test("following-feed backfill keeps its production composite index", () => {
  assert.equal(
    hasIndex("posts", [
      { fieldPath: "ownerCoupleId", order: "ASCENDING" },
      { fieldPath: "status", order: "ASCENDING" },
      { fieldPath: "publishedAt", order: "DESCENDING" },
    ]),
    true,
    "followCouple backfill queries published posts by owner and needs this production index"
  );
});
