// ASL auto-splitter for ColouredWorlds to be used in LiveSplitter
// 
// Game: ColouredWorlds (https://cerise.moe/jeux/ColouredWorlds.zip)
// Author: delthas (delthas@dille.cc) (https://github.com/Delthas/ASL/)
// Creation date: 2017-10-09
// License: MIT
// Version: 1.0
//
// Even though the game itself is pretty niche, the functions used can
// be applied to any Love2D game (compiled with LuaJIT). You may have
// to edit the "vars.Registry" static pointer path since the love DLL
// might change. The hash table algorithms should stay valid though.
//
// A quick starter on how LuaJIT stores tables/modules:
//
// Every table (array/object/...) is implemented as a hashtable,
// indexed by: for arrays, an index; for objects (fields), the
// (hash of the) string literally used in the code. For example
// if you declare game.state = {} in your code, the game hash table
// contains {} for the key "state".
//
// Regarding the fields part, each table has an array of nodes,
// and each node can contain a pointer to another node stored
// elsewhere. This is pretty much an array of linked lists.
// <hash % table_size> is the index into the array, then you need
// to search down the linked list until the key of the node you find
// is the right one.
// 
// Regarding the hierarchy of the tables: a global registry (actually a
// table), holds the "_LOADED" table, which stores all the loaded modules
// e.g. everything that has been loaded with require("stuff"), which
// themselves are tables that contain their fields, which can be e.g.
// numbers, or tables, in which case they may contain other tables, ...
// 
// Also, the only LuaJIT implementation for numbers is the C double.
// This might help you when searching for fields.
//
// If you want to delve deep into the LuaJIT code, you can find it here:
// http://luajit.org/download.html (I have used LuaJIT 2.0.3).
// You may want to check which exact version of LuaJIT the version of Love2D
// you use uses.
// You will find most of the structs in lj_obj.h and table-related code
// in lj_tab.c. Good luck!
//
//

// No static pointer path, so nothing to be put in the state action
state("ColouredWorlds"){}

// Functions that will be of use later (that's what you're looking for
// if creating a splitter for a Love2D game)
startup
{
	// Get the hash of the passed string, to be used in LuaJIT hash tables.
	vars.GetHash = (Func<string, int>)((str) =>
	{
		uint h = (uint)str.Length;
		uint a, b;
		if(str.Length >= 4) {
			a = (uint)str[0] | (uint)str[1] << 8 | (uint)str[2] << 16 | (uint)str[3] << 24;
			h ^= (uint)str[str.Length - 4] | (uint)str[str.Length - 3] << 8 | (uint)str[str.Length - 2] << 16 | (uint)str[str.Length - 1] << 24;
			int b_off = (str.Length >> 1) - 2;
			b = (uint)str[b_off] | (uint)str[b_off + 1] << 8  | (uint)str[b_off + 2] << 16  | (uint)str[b_off + 3] << 24;  
			h ^= b;
			h -= (b << 14) | (b >> 32 - 14);
			b_off = (str.Length >> 2) - 1;
			b += (uint)str[b_off] | (uint)str[b_off + 1] << 8 | (uint)str[b_off + 2] << 16 | (uint)str[b_off + 3] << 24;  
		} else if(str.Length > 0) {
			a = (uint)str[0];
			h ^= (uint)str[str.Length - 1];
			b = (uint)str[str.Length >> 1];
			h ^= b;
			h -= (b << 14) | (b >> 32 - 14);
		} else {
			return 0;
		}
		a ^= h;
		a -= (h << 11) | (h >> 32 - 11);
		b ^= a;
		b -= (a << 25) | (a >> 32 - 25);
		h ^= b;
		h -= (b << 16) | (b >> 32 - 16);
		return (int)h;
	});
	
	// Returns the 32-bit little-endian integer stored at the specified address.
	vars.ReadPointer = (Func<int, int>)((ptr) =>
	{
		return ExtensionMethods.ReadValue<int>(vars.Memory, new IntPtr(ptr));
	});

	// Gets the value/address of the object with the specified key in the specified table.
	// ptr: the address of the (beginning of) the hash table struct
	// key: the key of the object (that is, the actual in-code name of the field/...)
	// deref: whether to deref the obtained value (should be false for numbers, true for others)
	vars.GetMapValue = (Func<int, string, bool, int>)((ptr, key, deref) =>
	{
		int size = vars.ReadPointer(ptr + 0x1C);
		int hash = vars.GetHash(key);
		int node = vars.ReadPointer(ptr + 0x14) + 0x18 * (hash & size);
		while(true) {
			if((uint)vars.ReadPointer(node + 0x0C) == 0xFFFFFFFB &&
				vars.ReadPointer(vars.ReadPointer(node + 0x08) + 0x08) == hash)
				return deref? vars.ReadPointer(node) : node;
			node = vars.ReadPointer(node + 0x10);
			if(node == 0)
				return node;
		}
	});
	
	// Gets the value/address of the object at the end of a "hash table chain".
	// This is equivalent to calling GetMapValue multiple times.
	// ptr: the address of the (beginning of) the first hash table struct
	// keys: the list of keys to use (the first one is used for the first hash table, ...)
	// derefLast: whether to deref the last obtained value (see GetMapValue#deref)
	vars.GetMapValueChain = (Func<int, string[], bool, int>)((ptr, keys, derefLast) =>
	{
		for(int i=0; i<keys.Length; i++)
		{
			ptr = vars.GetMapValue(ptr, keys[i], derefLast || i<keys.Length-1);
			if(ptr == 0)
				return ptr;
		}
		return ptr;
	});
	
	// Get a 32-bit pointer path specified by a module and a list of offsets.
	// module: the actual name of the module, e.g. "love.dll"
	// offsets: the list of offsets to use
	// Returns e.g. [[[module + offsets[0]] + offsets[1]] + offsets[2]].
	vars.GetPointerPath = (Func<string, int[], int>)((module, offsets) =>
	{
		int ptr = 0;
		foreach(ProcessModuleWow64Safe m in vars.Modules)
		{
			if(m.ModuleName == module)
			{
				ptr = m.BaseAddress.ToInt32();
				break;
			}
		}
		foreach(int offset in offsets)
		{
			if(ptr == 0)
				return ptr;
			ptr = vars.ReadPointer(ptr + offset);
		}
		return ptr;
	});

}

// Game-specific stuff (also an example on how to use the above functions)
init
{
	// Store the memory and modules for use in the startup{} block.
	vars.Memory = memory;
	vars.Modules = modules;

	// Get the address of the root registry hash table, stored in the LuaJIT global state struct.
	// [[["love.dll"+0x002AB900] + 0x14] + 0x02AC] is the local lua state struct
	// [[[["love.dll"+0x002AB900] + 0x14] + 0x02AC] + 0x08] is the the global state struct
	// [[[["love.dll"+0x002AB900] + 0x14] + 0x02AC] + 0x08] + 0x88] is the the registry hash table
	// This is what might change between Love2D versions, or game versions.
	// The 0x08 and 0x88 offsets will probably not change.
	// An easy way you can find the registry hash table is the following:
	// - Scan for the following pattern ("Grouped" on Cheat Engine):
	//   00 00 00 00 FF FF FF FF 00 00 00 00 FF FF FF FF
	//   00 00 00 00 §§ §§ §§ §§ ?? ?? ?? ?? ?? ?? 00 00 
	//   00 00 00 00 00 00 00 00
	// - Replace "§§ §§ §§ §§" with "?? ?? ?? ??".
	// - Take the pattern for which the value at "§§ §§ §§ §§" is the address
	//    of the beginning of the pattern.
	// - Add 48 (decimal) to the address of the beginning of the pattern, and deref it. That's it.
	//
	// Note: this is not currently doable with a signature scan because this data isn't stored in
	//       a module segment, but on the heap, whose bounds you can't know statically. You can 
	//       however do this once, manually, in Cheat Engine, and then do a pointer scan, and
	//       replace the path below with the found pointer path. Beware that the GetPointerPath
	//       doesn't exactly work like DeepPointer.
	vars.Registry = vars.GetPointerPath("love.dll", new[]{0x002AB900, 0x14, 0x02AC, 0x8, 0x88});
	
	// Once we have the registry hash table, we can obtain any field by following this path:
	// _LOADED (the table containing all the tables you can call "require(...)" on)
	// <module> (the table containing all the objects declared in the <module>)
	// <field> (the name of the field in <module>)
	// If there is a (sub-)field inside your field, just add it to the path, and so on.
	// e.g. for a.b.c.d.e where "a" is the module (e.g. require("a") appears in the code),
	// the path would be "_LOADED", "a", "b", "c", "d", "e"
	
	// If <module> is e.g. "love.physics" I believe the path needs to be
	// "_LOADED", "love", "physics", ..., not "_LOADED", "love.physics", ...
	
	// We want to get a double, which is a number, so we don't want to deref the last
	// address: pass false as last argument
	vars.ElapsedAddress = vars.GetMapValueChain(vars.Registry, new[]{"_LOADED", "game", "elapsed"}, false);
	
	// Build a memory watcher for the address
	vars.Elapsed = new MemoryWatcher<double>(new IntPtr(vars.ElapsedAddress));
	
}

// Usual splitter stuff
update
{
	// Update the memory watcher
	vars.Elapsed.Update(game);
}

gameTime
{
	return TimeSpan.FromSeconds(vars.Elapsed.Current);
}

isLoading
{
	return true;
}


