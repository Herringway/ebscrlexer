module parser;

import sjisish;

import std.algorithm;
import std.exception;
import std.logger;
import std.range;
import std.uni;
import std.utf;

Parser parse(const ubyte[] script) @safe {
	return Parser(script.toUTF);
}

enum TokenType {
	text,
	comment,
	label,
	functionName,
	functionParamStart,
	functionParam,
	functionParamSeparator,
	functionParamEnd,
	endOfFile,
}

struct Token {
	TokenType type;
	const(char)[] value;
}

struct Parser {
	private const(char)[] script;

	Token[] tokens;
	Token front() const {
		return tokens[0];
	}
	this(const(char)[] data) @safe {
		script = data;
		refillTokens();
	}
	void popFront() @safe {
		tokens = tokens[1 .. $];
		if (tokens.length == 0) {
			refillTokens();
		}
	}
	bool empty() @safe {
		return (tokens.length == 0) && (detectToken() == TokenType.endOfFile);
	}
	void refillTokens() @safe {
		script.popWhile!isWhite();
		final switch (detectToken()) {
			case TokenType.text:
				fetchText();
				break;
			case TokenType.comment:
				fetchComment();
				break;
			case TokenType.label:
				fetchLabel();
				break;
			case TokenType.functionName:
				fetchFunction();
				break;
			case TokenType.functionParamStart:
				fetchFunctionParamStart();
				break;
			case TokenType.functionParamEnd:
				fetchFunctionParamEnd();
				break;
			case TokenType.functionParam:
			case TokenType.functionParamSeparator:
				assert(0, "should not happen");
			case TokenType.endOfFile:
				break;
		}
	}
	TokenType detectToken() @safe {
		if (script.length == 0) {
			return TokenType.endOfFile;
		}
		const nextChar = script[0];
		if (nextChar.isLabelCharacter) {
			return TokenType.label;
		}
		if (nextChar == '@') {
			return TokenType.functionName;
		}
		if (nextChar == ';') {
			return TokenType.comment;
		}
		if (nextChar == '(') {
			return TokenType.functionParamStart;
		}
		if (nextChar == ')') {
			return TokenType.functionParamEnd;
		}
		return TokenType.text;
	}
	void fetchLabel() @safe {
		const endOfLabel = script.byCodeUnit.countUntil!(x => !x.isLabelCharacter);
		const labelText = script[0 .. endOfLabel >= 0 ? endOfLabel : $];
		tokens ~= Token(TokenType.label, labelText);
		script = script[labelText.length .. $];
	}
	void fetchComment() @safe {
		const endOfComment = script[1 .. $].byCodeUnit.countUntil!(x => x == '\n');
		const commentText = script[1 .. endOfComment >= 0 ? (endOfComment + 1) : $];
		tokens ~= Token(TokenType.comment, commentText);
		if (endOfComment >= 0) {
			script = script[commentText.length + 2 .. $];
		} else {
			script = script[commentText.length + 1 .. $];
		}
	}
	void fetchText() @safe {
		const endOfText = script.byCodeUnit.countUntil!(x => !x.isTextCharacter);
		const text = script[0 .. endOfText >= 0 ? endOfText : $];
		tokens ~= Token(TokenType.text, text);
		script = script[text.length .. $];
	}
	void fetchFunction() @safe {
		const endOfFunctionName = script[1 .. $].byCodeUnit.countUntil!(x => !x.isLabelCharacter);
		const functionNameText = script[1 .. endOfFunctionName >= 0 ? (endOfFunctionName + 1) : $];
		tokens ~= Token(TokenType.functionName, functionNameText);
		if (endOfFunctionName >= 0) {
			script = script[functionNameText.length + 1 .. $];
		}
	}
	void fetchFunctionParamEnd() @safe {
		tokens ~= Token(TokenType.functionParamStart, "(");
		tokens ~= Token(TokenType.functionParamEnd, ")");
		script = script[1 .. $];
	}
	void fetchFunctionParamStart() @safe {
		tokens ~= Token(TokenType.functionParamStart, "(");
		script = script[1 .. $];
		while (true) {
			enforce(script.length > 0, "Malformed function: got end of buffer, expecting ')'");
			const endOfFunctionParam = script.byCodeUnit.countUntil!(x => (x == ',') || (x == ')'));
			const functionParamText = script[0 .. endOfFunctionParam >= 0 ? endOfFunctionParam : $];
			if (functionParamText.length > 0) {
				tokens ~= Token(TokenType.functionParam, functionParamText);
				script = script[functionParamText.length .. $];
			}
			if (script[0] == ',') {
				tokens ~= Token(TokenType.functionParamSeparator, ",");
				script.popFront();
			} else if (script[0] == ')') {
				script.popFront();
				break;
			} else {
				assert(0, "Unexpected token");
			}
		}
		tokens ~= Token(TokenType.functionParamEnd, ")");
	}
}

void popWhile(alias func, R)(ref R range) {
	while (!range.empty && func(range.front)) {
		range.popFront();
	}
}

bool isLabelCharacter(dchar c) @safe {
	return c.among!('_', '!') || ((c >= 'a') && (c <= 'z')) || ((c >= 'A') && (c <= 'Z')) || ((c >= '0') && (c <= '9'));
}

bool isTextCharacter(dchar c) @safe {
	return !isLabelCharacter(c) && (c != '@') && (c != '\n');
}
