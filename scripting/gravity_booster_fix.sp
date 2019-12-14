#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <shavit>
#include <output_info_plugin>

bool gB_GravityActivated[MAXPLAYERS];
bool gB_Late;
bool gB_Enabled[MAXPLAYERS] = {true, ...};

float gF_GravityDeactivateTime[MAXPLAYERS];
float gF_OldGravity[MAXPLAYERS] = {1.0, ...};
float gF_CurrentGravity[MAXPLAYERS] = {1.0, ...};

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
	version = "2.0",
	url = "http://steamcommunity.com/id/kidfearless"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	gB_Late = late;

	return APLRes_Success;
}

public void OnPluginStart()
{
	RegConsoleCmd("sm_booster_fix", Command_BooserFix, "Disable the gravity booster fix");

	if(gB_Late)
	{
		HookTriggers();
	}
}

public void OnClientPutInServer(int client)
{
	gB_GravityActivated[client] = false;
	gF_OldGravity[client] = 1.0;
	gF_CurrentGravity[client] = 1.0;
	gF_GravityDeactivateTime[client] = 0.0;
	gB_Enabled[client] = true;
}

public void OnEntitiesReady()
{
	HookTriggers();
}

public Action OnTrigger( const char[] output, int caller, int activator, float delay )
{
	if(!IsValidEntity(caller) || !(0 < activator <= MaxClients) || !IsValidEntity(activator))
	{
		// LogError("INVALID ENTITY... IGNORING TRIGGER");
		return Plugin_Continue;
	}
	if(GetEntPropFloat(activator, Prop_Data, "m_flLaggedMovementValue") == 1.0)
	{
		// LogError("ACTIVATOR IS MOVING NORMALLY... IGNORING TRIGGER");
		return Plugin_Continue;
	}
	if(!gB_Enabled[activator])
	{
		// LogError("ACTIVATOR DOESN'T WANT THE FIX... IGNORING TRIGGER");
		return Plugin_Continue;
	}

	Entity ent;

	if(!GetOutputEntity(caller, ent))
	{
		// LogError("BAD ENTITY HANDLE RETURNED... IGNORING TRIGGER");
		return Plugin_Continue;
	}

	gravity_t gravity;
	if(!ParseEntity(ent, gravity))
	{
		// LogError("COULD NOT FIND VALID BOOSTER... IGNORING TRIGGER");
		ent.CleanUp();
		return Plugin_Continue;
	}

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
	gF_CurrentGravity[activator] = gravity.value;

	gF_GravityDeactivateTime[activator] = gravity.delay;
	

	ent.CleanUp();
	return Plugin_Continue;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	static int s_LastTick[MAXPLAYERS+1];

	if(gB_GravityActivated[client])
	{
		float speed = GetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue");

		gF_GravityDeactivateTime[client] -= (GetTickInterval() * speed);

		if(gF_GravityDeactivateTime[client] <= 0.0)
		{
			SetEntityGravity(client, gF_OldGravity[client]); // should this reset to old gravity, or the gravity set by trigger_multiple?
			gB_GravityActivated[client] = false;
			gF_CurrentGravity[client] = 1.0;
		}
		else
		{
			SetEntityGravity(client, gF_CurrentGravity[client]); // should this reset to old gravity, or the gravity set by trigger_multiple?
		}
	}

	s_LastTick[client] = tickcount;
	return Plugin_Continue;
}

void HookTriggers()
{
	HookEntityOutput("trigger_multiple", "OnTrigger", OnTrigger);
	HookEntityOutput("trigger_multiple", "OnStartTouch", OnTrigger);
	HookEntityOutput("trigger_multiple", "OnTouching", OnTrigger);
	HookEntityOutput("trigger_multiple", "OnEndTouch", OnTrigger);
}

bool ParseEntity(Entity ent, gravity_t grav)
{	
	bool foundLowGrav = false;
	bool foundNormalGrav = false;
	float normalGravDelay;
	int gravCount = 0;
	// Loop through the output list
	for(int i = 0; i < ent.OutputList.Length; ++i)
	{
		// Get the full output list at the current index
		Output out;
		ent.OutputList.GetArray(i, out);

		if(StrEqual(out.Target, "!activator", false)) // being done on player triggering action, dont interfere if it isnt
		{
			// Break the PARAMETERS into 2 strings, 0 for gravity and 1 for it's value
			char params[2][MEMBER_SIZE];
			ExplodeString(out.Parameters, " ", params, 2, MEMBER_SIZE);

			if(StrEqual(params[0], "gravity", false)) // Has an output with gravity
			{
				++gravCount;
				float gravity = StringToFloat(params[1]);
				if(gravity == 1.0)
				{
					normalGravDelay = out.Delay;
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
	// If this trigger brush is responsible for both low grav and normal grav and isn't doing some weird thing with setting mutliple gravities then we can use it.
	if(foundNormalGrav && foundLowGrav && gravCount == 2)
	{
		grav.delay = normalGravDelay;
		return true;
	}
	return false;
}

public Action Command_BooserFix(int client, int args)
{
	gB_Enabled[client] = !gB_Enabled[client];

	ReplyToCommand(client, "Toggled gravity booster fix (%i)", gB_Enabled[client]);
	return Plugin_Handled;
}