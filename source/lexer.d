module lexer;

import sjisish;

import std.algorithm;
import std.conv;
import std.exception;
import std.logger;
import std.range;
import std.uni;
import std.utf;

Lexer lex(const ubyte[] script) @safe {
	return Lexer(script.toUTF);
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

private auto generateFunction(alias f)() {
	static Token nextToken(scope ref Lexer lexer) @safe {
		return __traits(getMember, lexer, __traits(identifier, f))(__traits(parameters)[1 .. $]);
	}
	return &nextToken;
}
struct Lexer {
	private const(char)[] script;

	Token[] tokens;
	Token function(scope ref typeof(this)) @safe pure nextTokenFunction;
	Token front;
	@safe pure:
	this(const(char)[] data) scope {
		script = data;
		front = standardToken();
	}
	void popFront() scope {
		assert(nextTokenFunction);
		front = nextTokenFunction(this);
	}
	bool empty() const scope {
		return front.type == TokenType.endOfFile;
	}
	Token standardToken() return scope {
		script.popWhile!isWhite();
		final switch (detectToken()) {
			case TokenType.text:
				return fetchText();
			case TokenType.comment:
				return fetchComment();
			case TokenType.label:
				return fetchLabel();
			case TokenType.functionName:
				return fetchFunction();
			case TokenType.functionParamStart:
			case TokenType.functionParamEnd: //these are just ignored apparently?
				script = script[1 .. $];
				return standardToken();
			case TokenType.functionParam:
			case TokenType.functionParamSeparator:
				throw new LexerException(text("Unexpected token ", detectToken()));
			case TokenType.endOfFile:
				return Token(TokenType.endOfFile);
		}
	}
	TokenType detectToken() scope {
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
		if (nextChar == ',') {
			return TokenType.functionParamSeparator;
		}
		return TokenType.text;
	}
	Token fetchLabel() return scope {
		const endOfLabel = script.byCodeUnit.countUntil!(x => !x.isLabelCharacter);
		const labelText = script[0 .. endOfLabel >= 0 ? endOfLabel : $];
		script = script[labelText.length .. $];
		nextTokenFunction = generateFunction!standardToken;
		return Token(TokenType.label, labelText);
	}
	Token fetchComment() return scope {
		const endOfComment = script[1 .. $].byCodeUnit.countUntil!(x => x == '\n');
		const commentText = script[1 .. endOfComment >= 0 ? (endOfComment + 1) : $];
		if (endOfComment >= 0) {
			script = script[commentText.length + 2 .. $];
		} else {
			script = script[commentText.length + 1 .. $];
		}
		nextTokenFunction = generateFunction!standardToken;
		return Token(TokenType.comment, commentText);
	}
	Token fetchText() return scope {
		const endOfText = script.byCodeUnit.countUntil!(x => !x.isTextCharacter);
		const text = script[0 .. endOfText >= 0 ? endOfText : $];
		script = script[text.length .. $];
		nextTokenFunction = generateFunction!standardToken;
		return Token(TokenType.text, text);
	}
	Token fetchFunction() return scope {
		const endOfFunctionName = script[1 .. $].byCodeUnit.countUntil!(x => !x.isLabelCharacter);
		const functionNameText = script[1 .. endOfFunctionName >= 0 ? (endOfFunctionName + 1) : $];
		script = script[functionNameText.length + 1 .. $];
		nextTokenFunction = generateFunction!fetchFunctionParamStart;
		return Token(TokenType.functionName, functionNameText);
	}
	Token fetchFakeFunctionParamEnd() scope {
		nextTokenFunction = generateFunction!standardToken;
		return Token(TokenType.functionParamEnd, ")");
	}
	Token fetchFunctionParamStart() scope {
		if (detectToken() == TokenType.functionParamStart) {
			nextTokenFunction = generateFunction!fetchFunctionParamList;
		} else {
			nextTokenFunction = generateFunction!fetchFakeFunctionParamEnd;
		}
		if (!script.empty) {
			script.popFront();
		}
		return Token(TokenType.functionParamStart, "(");
	}
	Token fetchFunctionParamSeparatorOrEnd() scope {
		script.popWhile!isWhite();
		enforce!LexerException(script.length > 0, "Malformed function: got end of buffer, expecting ',' or ')'");
		if (script[0] == ',') {
			nextTokenFunction = generateFunction!fetchFunctionParamList;
			script.popFront();
			return Token(TokenType.functionParamSeparator, ",");
		} else if (script[0] == ')') {
			nextTokenFunction = generateFunction!standardToken;
			script.popFront();
			return fetchFakeFunctionParamEnd();
		} else {
			assert(0, "Unexpected token");
		}
	}
	Token fetchFunctionParamList() return scope {
		script.popWhile!isWhite();
		enforce!LexerException(script.length > 0, "Malformed function: got end of buffer, expecting ')'");
		const endOfFunctionParam = script.byCodeUnit.countUntil!(x => (x == ',') || (x == ')') || x.isWhite);
		const functionParamText = script[0 .. endOfFunctionParam >= 0 ? endOfFunctionParam : $];
		if (functionParamText.length > 0) {
			script = script[functionParamText.length .. $];
			nextTokenFunction = generateFunction!fetchFunctionParamSeparatorOrEnd;
			return Token(TokenType.functionParam, functionParamText);
		} else if (script[0] == ')') {
			script = script[1 .. $];
			nextTokenFunction = generateFunction!standardToken;
			return Token(TokenType.functionParamEnd, ")");
		} else {
			throw new LexerException("Unexpected token in function parameter list");
		}
	}
}

@safe pure unittest {
	import std.stdio;
	import std.algorithm : equal;
	import std.exception : assertThrown;
	import std.range : only;
	assert(Lexer("").empty);
	assert(Lexer("HELLO_WORLD").equal(only(Token(TokenType.label, "HELLO_WORLD"))));
	assert(Lexer("Ｗ").equal(only(Token(TokenType.text, "Ｗ"))));
	assert(Lexer(";hello world!").equal(only(Token(TokenType.comment, "hello world!"))));
	assert(Lexer(";").equal(only(Token(TokenType.comment, ""))));
	assert(Lexer("@fun()").equal(only(Token(TokenType.functionName, "fun"), Token(TokenType.functionParamStart, "("), Token(TokenType.functionParamEnd, ")"))));
	assert(Lexer("@").equal(only(Token(TokenType.functionName, ""), Token(TokenType.functionParamStart, "("), Token(TokenType.functionParamEnd, ")"))));
	assert(Lexer("@fun").equal(only(Token(TokenType.functionName, "fun"), Token(TokenType.functionParamStart, "("), Token(TokenType.functionParamEnd, ")"))));
	assert(Lexer("@fun(foo)").equal(only(Token(TokenType.functionName, "fun"), Token(TokenType.functionParamStart, "("), Token(TokenType.functionParam, "foo"), Token(TokenType.functionParamEnd, ")"))));
	assert(Lexer("@fun(  \n foo   )").equal(only(Token(TokenType.functionName, "fun"), Token(TokenType.functionParamStart, "("), Token(TokenType.functionParam, "foo"), Token(TokenType.functionParamEnd, ")"))));
	assert(Lexer("@fun(  \t foo,     bar   )").equal(only(Token(TokenType.functionName, "fun"), Token(TokenType.functionParamStart, "("), Token(TokenType.functionParam, "foo"), Token(TokenType.functionParamSeparator, ","), Token(TokenType.functionParam, "bar"), Token(TokenType.functionParamEnd, ")"))));
	assert(Lexer("@!").equal(only(Token(TokenType.functionName, "!"), Token(TokenType.functionParamStart, "("), Token(TokenType.functionParamEnd, ")"))));
	assert(Lexer("👀@fun").equal(only(Token(TokenType.text, "👀"), Token(TokenType.functionName, "fun"), Token(TokenType.functionParamStart, "("), Token(TokenType.functionParamEnd, ")"))));
	assert(Lexer("(").empty);
	assert(Lexer("()").empty);
	assert(Lexer(")").empty);
	assertThrown!LexerException(Lexer(",").front);
	assertThrown!LexerException(Lexer("@fun(").walkLength);
	assertThrown!LexerException(Lexer("@fun(,").walkLength);
	assertThrown!LexerException(Lexer("@fun(Ｗ").walkLength);
	assertThrown!LexerException(Lexer("@fun(,Ｗ").walkLength);
	assertThrown!LexerException(Lexer("@fun(a,").walkLength);
}

void popWhile(alias func, R)(ref R range) {
	while (!range.empty && func(range.front)) {
		range.popFront();
	}
}

bool isLabelCharacter(dchar c) @safe pure {
	return c.among!('_', '!') || ((c >= 'a') && (c <= 'z')) || ((c >= 'A') && (c <= 'Z')) || ((c >= '0') && (c <= '9'));
}

bool isTextCharacter(dchar c) @safe pure {
	return !isLabelCharacter(c) && (c != '@') && (c != '\n');
}

class LexerException : Exception {
	mixin basicExceptionCtors;
}
