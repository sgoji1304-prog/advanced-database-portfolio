// =====================================================================
// Portfolio 4: queries, aggregation, atomic update and index evidence.
// Run AFTER mongo_setup.js:
//     mongosh "mongodb://localhost:27017/citylib_nosql" --file mongo_queries.js
// =====================================================================

// Helper: summarise an explain() plan as "STAGE <- STAGE(index)" plus key counters.
function plan(cursor) {
  const e = cursor.explain('executionStats');
  const out = [];
  (function walk(p) {
    if (!p) return;
    if (p.queryPlan) walk(p.queryPlan);            // newer servers wrap the plan
    out.push(p.stage + (p.indexName ? '(' + p.indexName + ')' : ''));
    walk(p.inputStage);
    (p.inputStages || []).forEach(walk);
  })(e.queryPlanner.winningPlan);
  const s = e.executionStats;
  return { plan: out.join(' <- '), docsExamined: s.totalDocsExamined,
           keysExamined: s.totalKeysExamined, returned: s.nReturned, ms: s.executionTimeMillis };
}

print('\n=== Q1. Exact lookup by ISBN (one document replaces a 4-table join) ===');
printjson(db.books.findOne({ isbn: '9780000000042' }));

print('\n=== Q2. Full-text search on title ===');
printjson(db.books.find({ $text: { $search: 'Title 1234' } }, { title: 1, isbn: 1, _id: 0 }).limit(5).toArray());

print('\n=== Q3. Array query: bestsellers in Fiction ===');
printjson(db.books.find({ category: 'Fiction', tags: 'bestseller' }, { title: 1, tags: 1 }).limit(5).toArray());

print('\n=== Q4. Format-specific attribute: audiobooks longer than 10 hours ===');
printjson(db.books.find({ format: 'audiobook', 'attributes.duration_minutes': { $gt: 600 } },
                        { title: 1, 'attributes.duration_minutes': 1 }).limit(5).toArray());

print('\n=== Q5. Books that currently have an available copy (embedded array match) ===');
print('Count: ' + db.books.countDocuments({ copies: { $elemMatch: { status: 'available' } } }));

print('\n=== Q6. Aggregation: average rating and review count per category ===');
printjson(db.books.aggregate([
  { $unwind: '$reviews' },
  { $group: { _id: '$category', avgRating: { $avg: '$reviews.rating' }, reviews: { $sum: 1 } } },
  { $project: { category: '$_id', _id: 0, reviews: 1, avgRating: { $round: ['$avgRating', 2] } } },
  { $sort: { avgRating: -1 } }
]).toArray());

print('\n=== Q7. Aggregation: copies by status across the whole catalogue ===');
printjson(db.books.aggregate([
  { $unwind: '$copies' },
  { $group: { _id: '$copies.status', copies: { $sum: 1 } } },
  { $sort: { copies: -1 } }
]).toArray());

print('\n=== Q8. Atomic single-document update: borrow one copy ===');
const target = db.books.findOne({ copies: { $elemMatch: { status: 'available' } } });
const barcode = target.copies.find(c => c.status === 'available').barcode;
const borrow = () => db.books.updateOne(
  { _id: target._id, copies: { $elemMatch: { barcode: barcode, status: 'available' } } },
  { $set: { 'copies.$.status': 'on_loan' } });
print('Borrowing copy ' + barcode + ' of book ' + target._id);
print('First attempt  modifiedCount = ' + borrow().modifiedCount + '   (expected 1)');
print('Second attempt modifiedCount = ' + borrow().modifiedCount + '   (expected 0, copy no longer available)');
// restore so the script can be re-run
db.books.updateOne({ _id: target._id, 'copies.barcode': barcode }, { $set: { 'copies.$.status': 'available' } });

print('\n=== Q9. Index evidence: BEFORE vs AFTER for the Fiction + bestseller query ===');
const q = () => db.books.find({ category: 'Fiction', tags: 'bestseller' });
db.books.dropIndex('category_1_tags_1');
print('Without index: ' + JSON.stringify(plan(q())));
db.books.createIndex({ category: 1, tags: 1 });
print('With index   : ' + JSON.stringify(plan(q())));

print('\nISBN lookup plan (unique index): ' + JSON.stringify(plan(db.books.find({ isbn: '9780000000042' }))));
print('Unindexed field (publication_year) plan: ' + JSON.stringify(plan(db.books.find({ publication_year: 1999 }))));
