import lexer;
import std.file;
import std.stdio;

void main(string[] args) {
	writefln!"%(%s\n%)"(lex(cast(ubyte[])read(args[1])));
}
