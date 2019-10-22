#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <dump_parser>


char gS_StripperPath[PLATFORM_MAX_PATH];

ArrayList gA_Entites;
StringMap gSM_EntityList;

bool gB_GravityActivated[MAXPLAYERS];
bool gB_Late;

float gF_GravityDeactivateTime[MAXPLAYERS];
float gF_OldGravity[MAXPLAYERS];


enum struct gravity_t
{
	float delay;
	float value;
}

public Plugin myinfo = 
{
	name = "Gravity Booster Fix",
	author = "KiD Fearless",
	description = "Changes booster boost time depending on players current timescale... Code heavily based off slidybats gravity booster fix plugin.",
	version = "1.1",
	url = "http://steamcommunity.com/id/kidfearless"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	gB_Late = late;

	return APLRes_Success;
}

public void OnPluginStart()
{
	gA_Entites = new ArrayList(2);
	gSM_EntityList = new StringMap();
	GetCommandLineParam("+stripper_path", gS_StripperPath, PLATFORM_MAX_PATH, "addons/stripper");
	Format(gS_StripperPath, PLATFORM_MAX_PATH, "%s/IO/", gS_StripperPath);

	RegAdminCmd("sm_reparse_gravity", Command_Init, ADMFLAG_BAN);

	if(gB_Late)
	{
		Init();
		for(int i = 1; i <= MaxClients; ++i)
		{
			OnClientPutInServer(i);
		}
	}
}

public void OnClientPutInServer(int client)
{
	gB_GravityActivated[client] = false;
	gF_OldGravity[client] = 1.0;
	gF_GravityDeactivateTime[client] = 0.0;
	// SDKHook(client, SDKHook_StartTouch, OnStartTouch);
}

public void OnDumpFileReady()
{
	Init();
}

Action Init()
{
	gA_Entites.Clear();
	gSM_EntityList.Clear();

	// Get the current map display name
	char mapName[PLATFORM_MAX_PATH];
	GetCurrentMap(mapName, PLATFORM_MAX_PATH);
	GetMapDisplayName(mapName, mapName, PLATFORM_MAX_PATH);

	// Point to the location of the formatted output list
	char path[PLATFORM_MAX_PATH];
	FormatEx(path, PLATFORM_MAX_PATH, "%s%s.JSON", gS_StripperPath, mapName);
	// If an output list couldn't be found stop the operation

	// Open the file for reading, if an error occurs then log it
	if(!FileExists(path))
	{
		LogError("ERROR: COULD NOT FIND IO JSON FILE: %s", path);
		SetFailState("NO JSON FILE FOUND. UNLOADING PLUGIN");
		return Plugin_Handled;
	}

	File ioFile = OpenFile(path, "r");

	if(ioFile == null)
	{
		LogError("ERROR: COULD NOT OPEN IO JSON FILE: %s", path);
		return Plugin_Handled;
	}

	while(!IsEndOfFile(ioFile))
	{
		char buffer[2048];
		// Import a kv file from the line that was read.
		ioFile.ReadLine(buffer, 2048);
		KeyValues kv = new KeyValues("0");
		if(!kv.ImportFromString(buffer))
		{
			LogError("Could not parse kv file: '%s'", buffer);
			continue;
		}
		// Grab it's hammer id
		char hammerid[24];

		kv.GetString("hammerid", hammerid, 24);

		char counter[12];
		strcopy(counter, 12, "0");
		char output[2048];
		ArrayList outputStringList = new ArrayList(2048);
		// declare an int counter variable. run the HasString function to both check for it's existance and return it's value.
		// Then ONCE it's done increment the variable and format it into the counter.
		for(int i = 0; GetKVString(kv, counter, output, 2048); FormatEx(counter, 12, "%i", ++i))
		{
			outputStringList.PushString(output);
		}
		delete kv;
		gravity_t gravity;
		ParseEntity(outputStringList, gravity);
		delete outputStringList;
		// Push the arraylist into the entity list and grab it's index.
		if( gravity.delay > 0.0)
		{
			int index = gA_Entites.PushArray( gravity );

			// associate the index with the entities hammerid
			gSM_EntityList.SetValue(hammerid, index);
		}
	}

	HookTriggers();
	delete ioFile;
	return Plugin_Handled;
}

public Action OnTrigger( const char[] output, int caller, int activator, float delay )
{
	if(!IsValidEntity(caller) || !(0 < activator <= MaxClients))
	{
		return Plugin_Continue;
	}
	if(GetEntPropFloat(activator, Prop_Data, "m_flLaggedMovementValue") == 1.0)
	{
		return Plugin_Continue;
	}

	// Get the hammer id from the ent index
	int id = GetEntProp(caller, Prop_Data, "m_iHammerID");
	if(id < 1)
	{
		return Plugin_Continue;
	}

	// Convert it to a string
	char hammerid[24];
	IntToString(id, hammerid, 24);

	// use the hammer id to get it's arraylist index
	int index;
	if(!gSM_EntityList.GetValue(hammerid, index))
	{
		return Plugin_Continue;
	}

	gravity_t gravity;
	// Grab the arraylist containing the entities outputs
	gA_Entites.GetArray(index, gravity);
	// PrintToConsole(activator, "delay %f, gravity: %f", gravity.delay, gravity.value)
	gB_GravityActivated[activator] = true;
	float grav = GetEntityGravity(activator);
	// booster already activated on player before we could find the proper gravity, use default then.
	if(gravity.value != grav)
	{
		gF_OldGravity[activator] = grav;
	}
	else
	{
		gF_OldGravity[activator] = 1.0;
	}
	
	SetEntityGravity(activator, gravity.value);
	
	float speed = GetEntPropFloat(activator, Prop_Data, "m_flLaggedMovementValue");
	gF_GravityDeactivateTime[activator] = GetEngineTime() + (gravity.value / speed);
		
	return Plugin_Handled;
}

public Action OnPlayerRunCmd(int client)
{
	if(gB_GravityActivated[client] && (GetEngineTime() >= gF_GravityDeactivateTime[client]))
	{
		SetEntityGravity(client, gF_OldGravity[client]); // should this reset to old gravity, or the gravity set by trigger_multiple?
		gB_GravityActivated[client] = false;
	}
	return Plugin_Continue;
}

public Action Command_Init(int client, int args)
{
	Init();
	return Plugin_Handled;
}

stock void HookTriggers()
{
	HookEntityOutput("trigger_multiple", "OnTrigger", OnTrigger);
	HookEntityOutput("trigger_multiple", "OnStartTouch", OnTrigger);
	HookEntityOutput("trigger_multiple", "OnTouching", OnTrigger);
	HookEntityOutput("trigger_multiple", "OnEndTouch", OnTrigger);
}

public bool ParseEntity(ArrayList list, gravity_t grav)
{	
	bool foundLowGrav = false;
	bool foundNormalGrav = false;
	float normalGravDelay;
	
	// Loop through the output list
	for(int i = 0; i < list.Length; ++i)
	{
		// Get the full output list at the current index
		char buffer[256];
		list.GetString(i, buffer, 256);
		// Break it up into more managable parts
		char entity[OUTPUTSIZE][64];
		ExplodeString(buffer, ";", entity, OUTPUTSIZE, 64);

		if(StrEqual(entity[TARGETENTITY], "!activator", false)) // being done on player triggering action, dont interfere if it isnt
		{
			// Break the PARAMETERS into 2 strings, 0 for gravity and 1 for it's value
			char params[2][32];
			ExplodeString(entity[PARAMETERS], " ", params, 2, 32);

			if(StrEqual(params[0], "gravity", false)) // Has an output with gravity
			{
				float gravity = StringToFloat(params[1]);
				if(gravity == 1.0)
				{
					normalGravDelay = StringToFloat(entity[DELAY]);
					foundNormalGrav = true;
					if(normalGravDelay < 0.0)
					{
						normalGravDelay = 0.0;
					}
				}
				else if(gravity < 1.0)
				{
					grav.value = gravity;
					foundLowGrav = true;
				}
			}
		}
	}
	if(foundNormalGrav && foundLowGrav)
	{
		grav.delay = normalGravDelay;
	}
	
	return true;
}

/* Deletes the handles of an arraylist containing arraylists */
stock void ClearArrayList(ArrayList list)
{
	for(int i = 0; i < list.Length; ++i)
	{
		ArrayList temp = list.Get(i);
		delete temp;
	}
}

/* Deletes the handles of an arraylist containing arraylists that contain arraylists */
stock void ClearArrayListList(ArrayList list)
{
	for(int i = 0; i < list.Length; ++i)
	{
		ArrayList a = list.Get(i);
		ClearArrayList(a);
		delete a;
	}
}
