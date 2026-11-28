import { test } from "node:test";
import assert from "node:assert/strict";
import { statusTree, typeTone, typeLabel } from "./model.js";

const STATES = {
  unstarted: { name: "To Do", type: "unstarted", color: "#8f9ba8" },
  started: { name: "In Progress", type: "started", color: "#2f80ed" },
  completed: { name: "Done", type: "completed", color: "#2da44e" },
};
const issue = (identifier, typeName, stateType, story = null) => ({
  identifier,
  title: identifier,
  type: { name: typeName },
  state: STATES[stateType] ?? null,
  story,
});
const STORY_LINK = { identifier: "AB-10", title: "Hooks", state: STATES.started };
const bucketKeys = (group) => group.stories.map((b) => b.key);

test("orders groups To Do, In Progress, Done, No state", () => {
  const tree = statusTree([
    issue("CR-1", "Task", "none"),
    issue("CR-2", "Task", "completed"),
    issue("CR-3", "Task", "started"),
    issue("CR-4", "Task", "unstarted"),
  ]);
  assert.deepEqual(tree.map((g) => g.label), ["To Do", "In Progress", "Done", "No state"]);
});

test("nests tasks under their story and keeps Other last", () => {
  const [group] = statusTree([
    issue("AB-30", "Security Finding", "started"),
    issue("AB-10", "Story", "started"),
    issue("AB-12", "Task", "started", STORY_LINK),
  ]);
  assert.deepEqual(bucketKeys(group), ["AB-10", "other"]);
  assert.deepEqual(group.stories[0].items.map((i) => i.identifier), ["AB-12"]);
  assert.equal(group.stories[0].storyItem.identifier, "AB-10");
  assert.equal(group.count, 3);
});

test("builds a header from the link when the story is not in the list", () => {
  const [group] = statusTree([issue("AB-13", "Task", "unstarted", STORY_LINK)]);
  assert.equal(group.stories[0].story.title, "Hooks");
  assert.equal(group.stories[0].storyItem, null);
});

test("repeats the story header in each group", () => {
  const tree = statusTree([
    issue("AB-10", "Story", "started"),
    issue("AB-13", "Task", "unstarted", STORY_LINK),
    issue("AB-12", "Task", "started", STORY_LINK),
  ]);
  assert.deepEqual(tree.map(bucketKeys), [["AB-10"], ["AB-10"]]);
});

test("moves a story with no tasks to Other", () => {
  const [group] = statusTree([issue("AB-20", "Story", "completed")]);
  assert.deepEqual(bucketKeys(group), ["other"]);
  assert.deepEqual(group.stories[0].items.map((i) => i.identifier), ["AB-20"]);
});

test("typeTone and typeLabel", () => {
  assert.equal(typeTone("Story"), "story");
  assert.equal(typeLabel("Story"), "STORY");
  assert.equal(typeTone("task"), "task");
  assert.equal(typeLabel("task"), "TASK");
  assert.equal(typeTone("Security Finding"), "other");
  assert.equal(typeLabel("Security Finding"), "SECURI");
});

test("a parent of any type heads its tasks once", () => {
  const epicLink = { identifier: "CR-1", title: "CR-1", type: { name: "Epic" }, state: STATES.started };
  const [group] = statusTree([issue("CR-1", "Epic", "started"), issue("CR-2", "Task", "started", epicLink)]);
  assert.deepEqual(bucketKeys(group), ["CR-1"]);
  assert.equal(group.stories[0].storyItem.identifier, "CR-1");
});
