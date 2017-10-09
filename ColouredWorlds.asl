// ASL auto-splitter for ColouredWorlds to be used in LiveSplitter
// 
// Game: ColouredWorlds (https://cerise.moe/jeux/ColouredWorlds.zip)
// Author: delthas (delthas@dille.cc) (https://github.com/Delthas/ASL/)
// Creation date: 2017-10-09
// License: MIT
// Version: 1.1
//
// Even though the game itself is pretty niche, the functions used can
// be applied to any Love2D game (compiled with LuaJIT). You may have
// to edit the "lua local state" static pointer path. The hash table 
// algorithms should stay valid though.
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
// There is also another table, called the table of globals, that holds all
// the global variables in the code (those not explicitly created with
// "local").
// 
// Also, the only LuaJIT implementation for numbers is the C double (and
// and booleans). This might help you when searching for fields.
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

	// Get the address of the local LuaJIT state struct.
	//
	// The static pointer path I have found may be wrong, and may change between
	// Love2D versions/game versions. In this case you will have to find another one.
	//
	// The easiest way to (manually) find the address of the local LuaJIT state struct,
	// in order to make a pointer scan on it, is simply to get the address pointed at by
	// "THREADSTACK0-A0" in Cheat Engine. This works as of Love2D 0.10.2 and should keep
	// working for a while.
	// The reason this pointer cannot be used is that ASL doesn't support (semi-)static
	// pointer paths starting with a pointer relative to the main thread stack base.
	//
	// Beware that GetPointerPath doesn't exactly work like DeepPointer. Read the
	// documentation above.
	//
	// You'll probably have to change this.
	vars.LocalState = vars.GetPointerPath("MSVCR110.dll", new[]{0x000C8E2C, 0x6D8});
	
	// The local LuaJIT state contains a pointer to the global LuaJIT struct at offset
	// 0x8, which contains a pointer to the registry table at offset 0x88.
	// I believe these offsets will not change.
	vars.Registry = vars.ReadPointer(vars.ReadPointer(vars.LocalState + 0x8) + 0x88);
	
	// The local LuaJIT state contains a pointer to the global table at offset 0x24.
	// I believe this offset will not change.
	vars.Globals = vars.ReadPointer(vars.LocalState + 0x24);
	
	// Once the registry table and the globals table are loaded, any symbol can be loaded:
	// - for global variables, the variable path is:
	//   Globals -> <global name> -> ...
	//   e.g. for game.elapsed where game is a global variable:
	//   Globals -> "game" -> "elapsed"
	// - for variables in modules, the variable path is:
	//   Registry -> "_LOADED" -> <field name> -> ...
	//   e.g. for game.elapsed where game is a module loaded somewhere with require("game"):
	//   Registry -> "_LOADED" -> "game" -> "elapsed"
	//
	// However the variables shouldn't be searched right away because they're probably not all
	// loaded by the time the init function is called. We should do that in update instead,
	// repeateadly, until they're loaded.
	
	vars.Init = false;
	
}

update
{
	if(!vars.Init)
	{
		// Get the address of a field in a module: use Registry and _LOADED.
	
		// We want to get a double, which is a number, so we don't want to deref the last
		// address: pass false as last argument
		// The field we want to get is simply game.elapsed, where game is a module (e.g. require("game"))
		vars.ElapsedAddress = vars.GetMapValueChain(vars.Registry, new[]{"_LOADED", "game", "elapsed"}, false);
		
		// If the address is zero, we failed to load it, probably because the game hasn't
		// loaded it yet. Return early before doing anything else.
		if(vars.ElapsedAddress == 0x0) return;
	
		// Build a memory watcher for the address
		vars.Elapsed = new MemoryWatcher<double>(new IntPtr(vars.ElapsedAddress));
		
		// Do the same for other fields
		vars.LevelAddress = vars.GetMapValueChain(vars.Registry, new[]{"_LOADED", "game", "level"}, false);
		vars.Level = new MemoryWatcher<double>(new IntPtr(vars.LevelAddress));
		
		// This field is global ("utils"), so use the Globals table
		vars.MenuAddress = vars.GetMapValueChain(vars.Globals, new[]{"utils", "menu"}, false);
		// The menu field is a boolean. Booleans are special in LuaJIT:
		// - add 0x4 to the address given by GetMapValueChain to get their actual address
		// - the value for true is the 0xFFFFFFFD 32-bit integer
		// - the value for false is the 0xFFFFFFFE 32-bit integer
		vars.Menu = new MemoryWatcher<uint>(new IntPtr(vars.MenuAddress + 0x4));
		
		// We have initialized, stop doing this every frame.
		vars.Init = true;
	}
	
	// Update the memory watchers
	vars.Elapsed.Update(game);
	vars.Level.Update(game);
	vars.Menu.Update(game);
}

// Below is standard splitter code

gameTime
{
	if(!vars.Init) return null;
	return TimeSpan.FromSeconds(vars.Elapsed.Current);
}

isLoading
{
	return true;
}

start
{
	if(!vars.Init) return;
	if(vars.Level.Current >= 1 && vars.Menu.Current != 0xFFFFFFFD /* true */) {
		vars.MaxLevel = 1;
		return true;
	}
}

split
{
	if(!vars.Init) return;
	if(vars.Level.Current > vars.MaxLevel) {
		vars.MaxLevel = vars.Level.Current;
		return true;
	}
}

reset
{
	if(!vars.Init) return;
	if(vars.Menu.Current == 0xFFFFFFFD /* true */) {
		vars.MaxLevel = -1;
		return true;
	}
}

