module jvmmetadata;

import std.stdio;
import std.file;
import std.format;
import std.string;
import std.conv;
import std.algorithm, std.range;
import std.typecons;

import elf;

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
	
	long libBase = 0; // the base address of the library
	string libFile = null; // the file on disk of the library
	auto mapFile = File(format("/proc/%s/maps", pid));
	foreach(line; mapFile.byLine()) {
		if (libBase == 0 && endsWith(line, "jvm.so")) {
			libBase = to!long(line[0..12], 16); // get the start of the memory range
			
			// get the memory range of the mapping, this is a string like "7f5795f7a000-7f5797165000"
			const mapId = line[0..25];
			// we can then get a symlink to the local file for this mapping in /proc/pid/map_files/mapId
			libFile = format("/proc/%s/map_files/%s", pid, mapId);
			assert(exists(libFile));
		}
	}
	
	auto memory = File(format("/proc/%s/mem", pid));
	
	auto elf = ELF.fromFile(libFile);
	auto symbols = dumpSymbolTables(elf);
	foreach(name, sym; symbols) {
		writefln("%s: %s %s", name, sym.sectionIndex, sym.value);
	}
	
	auto typesBase = getSymbol(libBase, symbols, "gHotSpotVMTypes");
	typesBase = readLong(memory, typesBase); // deref
	if (typesBase == 0) {
		writeln("gHotSpotVMTypes not initialised in target vm");
		return;
	}
}

/// Returns a pointer to the data specified by the given symbol
long getSymbol(long libBase, ELFSymbol[string] symbols, string name) {
	return libBase + symbols[name].value;
}

/// Read a signed 64bit long from the file at the offset given
long readLong(File file, long offset) {
	file.seek(offset, SEEK_SET);
	return file.rawRead(new long[1])[0];
}

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

/// Read all symbols into a map indexed by the symbol name
ELFSymbol[string] dumpSymbolTables(ELF elf) {
	ELFSymbol[string] symbolMap;
	
	foreach (section; only(".symtab", ".dynsym")) {
		Nullable!ELFSection s = elf.getSection(section);
		
		if (!s.isNull) {
			auto symbols = SymbolTable(s.get).symbols();
			
			foreach (symbol; symbols) {
				if (symbol.name !in symbolMap) {
					symbolMap[symbol.name] = symbol;
				}
			}
		}
	}
	
	return symbolMap;
}
