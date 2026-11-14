// =====================================================================
// Portfolio 4: NoSQL (document model) for CityLib, using MongoDB.
//
// Run from THIS folder, after export_from_postgres.sql has created books.jsonl:
//     mongosh "mongodb://localhost:27017/citylib_nosql" --file mongo_setup.js
//
// What it does:
//   1. Reads the books exported from PostgreSQL (same case study, same data).
//   2. Enriches each book with fields a relational table handles badly:
//      format-specific attributes, tags and embedded reader reviews.
//   3. Loads everything into the `books` collection and creates indexes.
// =====================================================================
const fs = require('fs');

// ---------- 1. Read the relational export ----------
const lines = fs.readFileSync('books.jsonl', 'utf8').split('\n').filter(l => l.trim() !== '');
const books = lines.map(l => JSON.parse(l));
print(`Read ${books.length} books from books.jsonl`);

// ---------- 2. Enrich: schema-flexible attributes ----------
const FORMATS = ['print', 'ebook', 'audiobook'];
const TAGS = ['bestseller', 'new-arrival', 'award-winner', 'staff-pick', 'classic'];

function enrich(doc) {
  const id = doc._id;
  doc.format = FORMATS[id % 3];

  // Different formats carry DIFFERENT attributes. In SQL this needs many
  // nullable columns or extra tables; in a document it is just a sub-object.
  if (doc.format === 'print') {
    doc.attributes = { pages: 100 + (id * 37 % 600), language: 'English', hardcover: id % 2 === 0 };
  } else if (doc.format === 'ebook') {
    doc.attributes = { file_type: 'EPUB', file_size_mb: 1 + (id * 13 % 40), drm_protected: id % 4 === 0 };
  } else {
    doc.attributes = { duration_minutes: 120 + (id * 17 % 900), narrator: 'Narrator ' + (id % 25) };
  }

  // Array field: a book can have any number of tags.
  doc.tags = TAGS.filter((t, i) => (id + i) % 3 === 0);

  // Embedded reviews: read together with the book, so they live inside it.
  doc.reviews = [];
  if (id % 4 !== 0) {
    const n = 1 + (id % 4);
    for (let k = 1; k <= n; k++) {
      doc.reviews.push({
        member_id: 1 + ((id * 31 + k * 17) % 5000),
        rating: 1 + ((id + k * 3) % 5),
        comment: 'Review ' + k + ' of book ' + id,
        date: new Date(Date.now() - ((id * k) % 365) * 86400000)
      });
    }
  }
  return doc;
}

// ---------- 3. Load ----------
db.books.drop();
const enriched = books.map(enrich);
for (let i = 0; i < enriched.length; i += 500) {
  db.books.insertMany(enriched.slice(i, i + 500));
}
print(`Inserted ${db.books.countDocuments()} documents into citylib_nosql.books`);

// ---------- 4. Indexes (used and measured in mongo_queries.js) ----------
db.books.createIndex({ isbn: 1 }, { unique: true });          // exact lookup
db.books.createIndex({ category: 1, tags: 1 });               // compound + multikey (array)
db.books.createIndex({ title: 'text' });                      // full-text search
db.books.createIndex({ 'copies.status': 1 });                 // availability checks
print('Indexes created:');
printjson(db.books.getIndexes().map(i => i.name));

print('\nSample document:');
printjson(db.books.findOne({ _id: 7 }));
