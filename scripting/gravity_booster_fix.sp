#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <shavit>
#include <output_info_plugin>

enum struct gravity_t
{
	float time;
	float curGravity;
	float oldGravity;
	bool active;

	void Clear()
	{
		this.time = 0.0;
		this.curGravity = 1.0;
		this.oldGravity = 1.0;
		this.active = false;
	}
}

bool gB_Late;
bool gB_Enabled[MAXPLAYERS+1] = {true, ...};

ArrayList gA_Checkpoints[MAXPLAYERS+1];

gravity_t g_Gravity[MAXPLAYERS+1];


public Plugin myinfo = 
{
	name = "Gravity Booster Fix",
	author = "KiD Fearless",
	description = "Changes booster boost time depending on players current timescale",
	version = "2.1",
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
	g_Gravity[client].Clear();
	gB_Enabled[client] = true;
	delete gA_Checkpoints[client];
	gA_Checkpoints[client] = new ArrayList(sizeof(gravity_t));
}

public void OnEntitiesReady()
{
	HookTriggers();
}

public Action Shavit_OnSave(int client, int index, bool overflow)
{
	ArrayList checkPoint = gA_Checkpoints[client];
	gravity_t grav;
	grav = g_Gravity[client];

	// Add the current gravity onto it if it's a normal checkpoint
	if(index == checkPoint.Length)
	{
		checkPoint.PushArray(grav);
	}
	// If it somehow skipped a checkpoint then we try to create some empty ones
	else if(index > checkPoint.Length)
	{
		int oldSize = checkPoint.Length;
		checkPoint.Resize(index + 1);
		gravity_t emptyGrav;
		emptyGrav.Clear();

		for(int i = oldSize; i < checkPoint.Length; ++i)
		{
			checkPoint.SetArray(i, emptyGrav);
		}

		checkPoint.SetArray(index, grav);
	}
	// If they somehow went back then we just roll with it and update that index
	else
	{
		checkPoint.SetArray(index, grav);
	}

	// If we're overflowing then we need to remove the first checkpoint to prevent misalignment
	if(overflow)
	{
		checkPoint.Erase(0);
	}

	return Plugin_Continue;
}

public Action Shavit_OnTeleport(int client, int index)
{
	// don't set the gravity if they have it disabled
	if(!gB_Enabled[client])
	{
		return Plugin_Continue;
	}

	// don't try to read any gravities that don't exist
	ArrayList checkPoint = gA_Checkpoints[client];
	if(index >= checkPoint.Length)
	{
		return Plugin_Continue;
	}
	
	// get the gravity on that index and set it as the current
	gravity_t grav;
	checkPoint.GetArray(index, grav);
	g_Gravity[client] = grav;

	return Plugin_Continue;
}

public Action OnTrigger(const char[] output, int caller, int activator, float delay)
{
	// TODO: only set the gravity players gravity when they activate the output that sets it, not before.

	if(!IsValidEntity(caller) || !(0 < activator <= MaxClients) || !IsValidEntity(activator))
	{
		// LogError("INVALID ENTITY... IGNORING TRIGGER");
		return Plugin_Continue;
	}
	// don't check if we already got our gravity or don't want to run the plugin
	if(!gB_Enabled[activator] || g_Gravity[activator].active)
	{
		// LogError("ACTIVATOR DOESN'T WANT THE FIX... IGNORING TRIGGER");
		return Plugin_Continue;
	}

	Entity ent;

	if(!GetOutputEntity(caller, ent) || ent.OutputList.Length == 0)
	{
		ent.CleanUp();
		// LogError("BAD OUTPUT ENTITY RETURNED... IGNORING TRIGGER");
		return Plugin_Continue;
	}

	// Check to see if booster contains both set and reset gravity outputs
	if(!ParseEntity(ent, g_Gravity[activator]))
	{
		// LogError("COULD NOT FIND VALID BOOSTER... IGNORING TRIGGER");
		ent.CleanUp();
		g_Gravity[activator].Clear();
		return Plugin_Continue;
	}

	g_Gravity[activator].active = true;
	g_Gravity[activator].oldGravity = GetEntityGravity(activator);
	
	
	SetEntityGravity(activator, g_Gravity[activator].curGravity);

	ent.CleanUp();

	return Plugin_Continue;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	if(gB_Enabled[client] && g_Gravity[client].active)
	{
		if(g_Gravity[client].time <= 0.0)
		{
			SetEntityGravity(client, g_Gravity[client].oldGravity);
			g_Gravity[client].active = false;
		}
		else
		{
			float speed = GetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue");
	
			g_Gravity[client].time -= (GetTickInterval() * speed);
			SetEntityGravity(client, g_Gravity[client].curGravity);
		}
	}
	
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
	bool foundLowGrav;
	bool foundNormalGrav;
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
					grav.curGravity = gravity;
					foundLowGrav = true;
				}
			}
		}
	}
	// If this trigger brush is responsible for both low grav and normal grav and isn't doing some weird thing with setting mutliple gravities then we can use it.
	if(foundNormalGrav && foundLowGrav && gravCount == 2)
	{
		grav.time = normalGravDelay;
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