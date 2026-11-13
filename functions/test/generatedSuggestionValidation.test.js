const assert = require("node:assert/strict");
const test = require("node:test");

const {
  GeneratedSuggestionValidationError,
  validateGeneratedSuggestions,
} = require("../lib/dateSuggestions/generatedSuggestionValidation.js");

function suggestion(title, placeHint = "Landgrafenschloss Marburg") {
  return {
    title,
    summary: "Ein entspannter Abend mit einem schönen Blick über die Stadt.",
    moodTags: ["entspannt"],
    estimatedBudgetLevel: "mittel",
    stations: [{
      title: "Spaziergang zum Landgrafenschloss",
      category: "sight",
      searchQueryHint: placeHint,
      description: "Ihr startet mit einem kurzen Spaziergang zum Aussichtspunkt.",
      estimatedDurationMinutes: 60,
    }, {
      title: "Kaffee im Vetter Café",
      category: "cafe",
      searchQueryHint: "Vetter Café Marburg",
      description: "Danach gibt es etwas Süßes und einen ruhigen Abschluss.",
      estimatedDurationMinutes: 60,
    }],
  };
}

function fiveSuggestions(first = "Schlossblick am Abend") {
  return [
    suggestion(first),
    suggestion("Kaffee am Grün", "Botanischer Garten Marburg"),
    suggestion("Lichter über der Lahn", "Elisabethkirche Marburg"),
    suggestion("Blick über die Altstadt", "Spiegelslustturm Marburg"),
    suggestion("Kleine Auszeit", "Alter Botanischer Garten Marburg"),
  ];
}

test("concrete local routes pass the generated-suggestion guard", () => {
  const result = validateGeneratedSuggestions(fiveSuggestions(), "Marburg");

  assert.equal(result.length, 5);
  assert.equal(result[0].stations[0].searchQueryHint, "Landgrafenschloss Marburg");
});

test("a bare place category is rejected before it reaches the app", () => {
  assert.throws(
    () => validateGeneratedSuggestions([
      suggestion("Standard-Abend", "Restaurant Marburg"),
      ...fiveSuggestions().slice(1),
    ], "Marburg"),
    GeneratedSuggestionValidationError
  );
});

test("a named place without a repeated city is completed for the selected MapKit search", () => {
  const result = validateGeneratedSuggestions([
    suggestion("Schloss ohne Ortszusatz", "Landgrafenschloss"),
    ...fiveSuggestions().slice(1),
  ], "Marburg", { appendCityToSpecificHints: true });

  assert.equal(result[0].stations[0].searchQueryHint, "Landgrafenschloss, Marburg");
});

test("a route for a different city or an implausible stop duration is rejected", () => {
  const invalidCity = suggestion("Falsche Stadt", "Landgrafenschloss Kassel");
  const invalidDuration = suggestion("Zu lang");
  invalidDuration.stations[0].estimatedDurationMinutes = 500;

  assert.throws(
    () => validateGeneratedSuggestions([invalidCity, ...fiveSuggestions().slice(1)], "Marburg"),
    GeneratedSuggestionValidationError
  );
  assert.throws(
    () => validateGeneratedSuggestions([invalidDuration, ...fiveSuggestions().slice(1)], "Marburg"),
    GeneratedSuggestionValidationError
  );
});

test("a route must fit the selected total duration when a target is supplied", () => {
  const tooLong = fiveSuggestions();
  tooLong.forEach((item) => item.stations.forEach((station) => { station.estimatedDurationMinutes = 180; }));

  assert.throws(
    () => validateGeneratedSuggestions(tooLong, "Marburg", { targetDurationMinutes: 120 }),
    GeneratedSuggestionValidationError
  );
  assert.equal(
    validateGeneratedSuggestions(fiveSuggestions(), "Marburg", { targetDurationMinutes: 120 }).length,
    5
  );
});
