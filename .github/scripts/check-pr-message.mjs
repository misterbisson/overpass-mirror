// Validates the commit message a squash-merge of this PR would produce.
//
// Merges here are squash-only, so GitHub builds the commit message from the PR
// *title* (plus " (#N)") and the PR *description* -- not from the branch's own
// commits. release-please then parses that message to decide whether a release
// happens at all. So the PR description is load-bearing release input, which is
// not obvious while writing one.
//
// Two failure modes are silent without this check: a message that does not parse
// as a Conventional Commit, and one that parses but uses a type release-please
// does not recognize. Both produce no changelog entry, no version bump, and a
// green check. This turns both into a red check on the PR instead.
//
// Deliberately runs the *same* parser release-please uses, rather than a regex
// approximation of Conventional Commits. An approximation would disagree with
// the real thing at exactly the margins where this check earns its keep.

import { parser, toConventionalChangelogFormat } from '@conventional-commits/parser';

// Types release-please recognizes. A message parses fine with any type -- `wip:`
// is structurally valid -- so an unknown type is a silent failure: no changelog
// entry, no version bump, no error. Checked separately below, because the parser
// will not complain about it.
const RELEASE_WORTHY = new Set(['feat', 'fix']);
const KNOWN_TYPES = new Set([
	'feat', 'fix', 'docs', 'chore', 'refactor', 'test',
	'style', 'perf', 'build', 'ci', 'revert',
]);

const title = process.env.PR_TITLE ?? '';
const body = process.env.PR_BODY ?? '';
const number = process.env.PR_NUMBER ?? '0';

// Mirror GitHub's squash-merge default: title gets " (#N)" appended, body follows
// after a blank line.
const message = `${title} (#${number})\n\n${body}`;

function fail(lines) {
	console.error(lines.join('\n'));
	process.exit(1);
}

// A narrow but easy-to-hit parse failure worth diagnosing by hand.
//
// The parser reads a line beginning with `identifier(` as the start of a scoped
// header -- `type(scope): subject` -- so a nested `(` inside that group is a
// syntax error, since a scope cannot contain one. It only triggers at column 0:
// indenting the line by a single space, or putting any word before the call,
// parses fine. Flat calls like `foo(a, b)` at column 0 are also fine.
//
// A fenced code block in a PR description is the natural way to hit it -- a line
// like `render(build(x), opts)` at column 0 is exactly the shape.
function diagnoseLineStartCall(msg) {
	const lines = msg.split('\n');
	for (let i = 0; i < lines.length; i++) {
		const line = lines[i];
		const m = /^[A-Za-z_$][\w$.]*\(/.exec(line);
		if (!m) continue;
		// Only a nested opening paren inside the group is a problem.
		const rest = line.slice(m[0].length);
		if (/[([]/.test(rest.split(')')[0] ?? '')) {
			return { lineNumber: i + 1, line };
		}
	}
	return null;
}

let ast;
try {
	ast = parser(message);
} catch (error) {
	const hint = diagnoseLineStartCall(message);
	const out = [
		'This PR\'s squash-merge commit message will not parse as a Conventional Commit.',
		'',
		`  ${error.message}`,
		'',
	];
	if (hint) {
		out.push(
			`Most likely line ${hint.lineNumber} of the squash message:`,
			'',
			`  ${hint.line}`,
			'',
			'A line starting at column 0 with a function call that has a nested call',
			'inside its arguments is read as a scoped header, and a scope cannot contain',
			'a parenthesis. Indenting that line by one space fixes it, and so does any',
			'word before the call. This only triggers at column 0.',
			'',
		);
	}
	out.push(
		'Remember the squash message is the PR *title* plus the PR *description*,',
		'so the offending line is usually in the description rather than in a commit.',
		'',
		'If this is not fixed, release-please skips the commit silently: no changelog',
		'entry, no version bump, and a green check.',
	);
	fail(out);
}

let conventional;
try {
	conventional = toConventionalChangelogFormat(ast);
} catch (error) {
	fail([
		'The squash message parsed but could not be read as a Conventional Commit.',
		'',
		`  ${error.message}`,
	]);
}

const { type } = conventional;
const breaking = conventional.notes.some((note) => note.title === 'BREAKING CHANGE');

if (!KNOWN_TYPES.has(type)) {
	fail([
		`Unrecognized commit type "${type}".`,
		'',
		`Known types: ${[...KNOWN_TYPES].join(', ')}`,
		'',
		'This is the quieter of the two failures: the message parses, so nothing errors,',
		'but release-please does not recognize the type and silently produces no changelog',
		'entry and no version bump.',
	]);
}

const effect = breaking
	? 'BREAKING -- a minor bump while the version is pre-1.0, per bump-minor-pre-major'
	: RELEASE_WORTHY.has(type)
		? `${type} -- release-worthy, will appear in the changelog`
		: `${type} -- deliberately not release-worthy, no changelog entry`;

console.log(`Squash message parses. Type: ${effect}`);
