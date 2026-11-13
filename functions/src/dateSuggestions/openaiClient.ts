import OpenAI from "openai";
import type { RawSuggestion } from "./types";

const submitDateSuggestionsFunction = {
  type: "function" as const,
  name: "submit_date_suggestions",
  description: "Submit exactly five structured route variants. Each variant must have the same two or three station slots, so people can mix and match one option per slot.",
  strict: true,
  parameters: {
    type: "object",
    properties: {
      suggestions: {
        type: "array",
        minItems: 5,
        maxItems: 5,
        items: {
          type: "object",
          properties: {
            title: { type: "string" },
            summary: { type: "string" },
            moodTags: { type: "array", items: { type: "string" } },
            estimatedBudgetLevel: { type: "string", enum: ["guenstig", "mittel", "gehoben"] },
            stations: {
              type: "array",
              minItems: 2,
              maxItems: 3,
              items: {
                type: "object",
                properties: {
                  title: { type: "string" },
                  category: {
                    type: "string",
                    enum: [
                      "restaurant", "cafe", "bar", "park", "museum", "cinema",
                      "theater", "sight", "activity", "shopping", "nature", "nightlife", "other",
                    ],
                  },
                  searchQueryHint: { type: "string" },
                  description: { type: "string" },
                  estimatedDurationMinutes: { type: "integer" },
                },
                required: ["title", "category", "searchQueryHint", "description", "estimatedDurationMinutes"],
                additionalProperties: false,
              },
            },
          },
          required: ["title", "summary", "moodTags", "estimatedBudgetLevel", "stations"],
          additionalProperties: false,
        },
      },
    },
    required: ["suggestions"],
    additionalProperties: false,
  },
};

/**
 * OpenAI equivalent of the (removed) Anthropic claudeClient — same forced
 * tool-use discipline, same submit_date_suggestions contract, so nothing
 * downstream (generateDateSuggestions.ts, the iOS client) had to change.
 * Uses the Responses API with a forced function call rather than
 * prose-JSON parsing, for the same reliability reason as the Claude version.
 */
export async function callOpenAI(
  systemPrompt: string,
  userContent: string,
  model: string,
  apiKey: string
): Promise<{ suggestions: RawSuggestion[] }> {
  const openai = new OpenAI({ apiKey, maxRetries: 0, timeout: 45_000 });
  const response = await openai.responses.create({
    model,
    max_output_tokens: 8_000,
    instructions: systemPrompt,
    input: userContent,
    tools: [submitDateSuggestionsFunction],
    tool_choice: { type: "function", name: "submit_date_suggestions" },
  });

  console.info("MITE_MODEL_USAGE", JSON.stringify({ model: response.model, inputTokens: response.usage?.input_tokens, outputTokens: response.usage?.output_tokens }));

  // Same "never assume shape from a 200" discipline as the removed Claude client:
  // find the function_call output explicitly rather than indexing output[0].
  const functionCall = response.output.find(
    (item): item is Extract<typeof item, { type: "function_call" }> =>
      item.type === "function_call" && item.name === "submit_date_suggestions"
  );
  if (!functionCall) {
    throw new Error(`Expected a submit_date_suggestions function_call output, got: ${JSON.stringify(response.output.map((i) => i.type))}`);
  }

  let parsed: { suggestions: RawSuggestion[] };
  try {
    parsed = JSON.parse(functionCall.arguments);
  } catch {
    throw new Error("Could not parse submit_date_suggestions arguments as JSON.");
  }
  return parsed;
}
