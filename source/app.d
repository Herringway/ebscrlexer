import parser;
import std.file;
import std.stdio;

void main(string[] args) {
	writefln!"%(%s\n%)"(parse(cast(ubyte[])read(args[1])));
}
