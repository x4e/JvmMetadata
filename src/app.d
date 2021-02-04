module jvmmetadata;

import std.stdio;
import std.file;
import std.format;
import std.string;
import std.conv;
import std.algorithm, std.range;
import std.typecons;

import elf;

/// Return true if the given string contains only numeric characters.
/// Signs and decimal points are not considered numeric characters.
bool isInteger(const string str) {
	foreach (const char c; str) {
		if (c < '0' || c > '9') {
			return false;
		}
	}
	return true;
}

/// Is the pid a valid folder in /proc/
bool validProcess(const string pid) {
	return exists(format("/proc/%s", pid));
}

void main(const string[] args) {
	// First print all Java processes
	foreach(const string filename; dirEntries("/proc/", SpanMode.shallow)) {
		// Remove /proc/ part
		const pid = filename[6..$];
		
		// Proc contains some stuff like "sys" that we want to ignore
		if (isInteger(pid)) {
			// Get the command name (e.g. "java")
			const command = strip(readText(format("%s/comm", filename)));
			if (command == "java") {
				// Get the full command line, this is a null delimited string so replace nulls with space
				const cmdline = strip(readText(format("%s/cmdline", filename)).replace("\u0000", " "));
				writefln("%s:\t%s", pid, cmdline);
			}
		}
	}
	
	string pid;
	do {
		write("Select a pid: ");
		pid = strip(readln());
	} while (!validProcess(pid));
	
	string libFile = null;
	auto mapFile = File(format("/proc/%s/maps", pid));
	foreach(line; mapFile.byLine()) {
		if (endsWith(line, "jvm.so")) {
			// get the id of the mapping, this is like "7f5795f7a000-7f5797165000"
			const mapId = line[0..25];
			// we can then get a symlink to the local file for this mapping in /proc/pid/map_files/mapId
			libFile = format("/proc/%s/map_files/%s", pid, mapId);
			assert(exists(libFile));
		}
	}
	
	auto elf = ELF.fromFile(libFile);
	printSymbolTables(elf);
}

void printSymbolTables(ELF elf) {
	writeln();
	writeln("Symbol table sections contents:");

	foreach (section; only(".symtab", ".dynsym")) {
		Nullable!ELFSection s = elf.getSection(section);
		
		if (!s.isNull) {
			auto symbols = SymbolTable(s.get).symbols();
			
			foreach (symbol; symbols) {
				writefln("%s %s %s: %s %s", symbol.binding, symbol.type, symbol.name, symbol.value, symbol.size);
			}
		}
	}
}
