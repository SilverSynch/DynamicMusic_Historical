import glob
import fileinput
import json5 as json # this is required because some MUSE2 mods have cursed json with trailing commas.
import enum
import os
import sys
import fnmatch
import re
import ffmpeg # ffmpeg-python, rather than python-ffmpeg. The latter does not support extracting info about the music file.
import luadata

def insensitive_glob(pattern): # I live in a hell where case sensitivity is a major problem.
    def either(c):
        return '[%s%s]' % (c.lower(), c.upper()) if c.isalpha() else c
    return glob.glob(''.join(map(either, pattern)))

# invoke this script as ./dynamtranslate.py [MOD NAME SHORTHAND]. Avoid translating more than one MUSE2 mod at a time, their file names can overlap.

music_lists = glob.glob("./*.json") # get all json files in this folder. hint: run this script in the /MWSE/config/MS/ folder of the MUSE2 mod.
Type = enum.Enum("Type", "REGION CELL TILESET OVERRIDE ENEMY")

for f in music_lists:
    with open(f, encoding="utf-8") as jsonfile:
        jsondata = json.load(jsonfile)

        if ("dungeonFolder" in jsondata) or ("airFolder" in jsondata) or ("depthsFolder" in jsondata):  # Dynamic Music won't support it directly, but we can dump the track list for use elsewhere
            filetype = Type.OVERRIDE
        elif "cellNamePart" in jsondata:
            filetype = Type.CELL
        elif "regionName" in jsondata:
            filetype = Type.REGION
        elif "enemyNames" in jsondata: # Dynamic Music won't support it directly, but we can dump the track list for use elsewhere
            filetype = Type.ENEMY
        elif "tilesetPart" in jsondata: # Dynamic Music won't support it directly, but we can dump the track list for use elsewhere
            filetype = Type.TILESET
        else: # on fallthrough just abort this file, we've accidentally read something other than a MUSE2 list.
            continue

        new_file_path = jsonfile.name.removesuffix("json")
        new_file_path = new_file_path.lower()
        if filetype is Type.CELL:
            new_file_path = new_file_path.replace("ms_c", "0000_" + sys.argv[1] + "_cell") + "lua"
        elif filetype is Type.REGION:
            new_file_path = new_file_path.replace("ms_r", "0000_" + sys.argv[1] + "_region") + "lua"
        elif filetype is Type.ENEMY:
            new_file_path = new_file_path.replace("ms_e", "0000_" + sys.argv[1] + "_enemy") + "lua" # it will be parsed, but Dynamic Music will be blocked from loading it.
        elif filetype is Type.TILESET:
            new_file_path = new_file_path.replace("ms_t", "0000_" + sys.argv[1] + "_tileset") + "lua"
        elif filetype is Type.OVERRIDE:
            new_file_path = new_file_path.replace("ms_o", "0000_" + sys.argv[1] + "_override") + "lua"

        databank_id = new_file_path.removesuffix(".lua").removeprefix("./0000_")

        if filetype is Type.CELL:
            found_tracks = insensitive_glob("../../../music/MS/cell/" + jsondata["folder"] +"/*.mp3")
        elif filetype is Type.REGION:
            found_tracks = insensitive_glob("../../../music/MS/region/" + jsondata["folder"] +"/*.mp3")
        elif filetype is Type.TILESET:
            found_tracks = insensitive_glob("../../../music/MS/interior/" + jsondata["folder"] +"/*.mp3")
        elif filetype is Type.ENEMY:
            found_tracks = insensitive_glob("../../../music/MS/combat/" + jsondata["folder"] +"/*.mp3")
        elif filetype is Type.OVERRIDE:
            found_tracks = list(set(insensitive_glob("../../../music/MS/general/" + jsondata["dungeonFolder"] +"/*.mp3") + insensitive_glob("../../../music/MS/general/" + jsondata["airFolder"] +"/*.mp3") + insensitive_glob("../../../music/MS/general/" + jsondata["depthsFolder"] +"/*.mp3")))

        runtimes = [int(round(float(ffmpeg.probe(item)['format']['duration']))) for item in found_tracks]

        found_tracks_culled = [item.removeprefix("../../../") for item in found_tracks]

        built_tracklist = [dict(path = path, length = length) for path, length in zip(found_tracks_culled, runtimes)]

        final_dict = dict()
        final_dict["id"] = databank_id
        if filetype is Type.CELL:
            final_dict["cellNamePatterns"] = jsondata["cellNamePart"]
            if "cellNameExclude" in jsondata:
                final_dict["cellNamePatternsExclude"] = jsondata["cellNameExclude"]
        elif filetype is Type.REGION:
            final_dict["regionNames"] = jsondata["regionName"]
        elif filetype is Type.ENEMY:
  # the empty cell name patterns means these tracks will never play, but are still written, so they can be fixed manually.
            final_dict["enemyNames"] = jsondata["enemyNames"]
        elif filetype is Type.TILESET:
            final_dict["tilesetPatterns"] = jsondata["tilesetPart"]
        elif filetype is Type.OVERRIDE:
            final_dict["cellNamePatterns"] = []

        if filetype is Type.ENEMY:
            final_dict["combatTracks"] = built_tracklist
        elif filetype is Type.OVERRIDE and "combatDisable" in jsondata and jsondata["combatDisable"] == true:
            final_dict["combatTracks"] = built_tracklist # attempt to add override tracks to combat tracks if they're meant to override combat tracks.
            final_dict["tracks"] = built_tracklist
        else:
            final_dict["tracks"] = built_tracklist


        final_file = "local soundBank = " + luadata.serialize(final_dict, indent ="  ", indent_level=0) + "\nreturn soundBank"


        with open(new_file_path, mode='w', encoding="utf-8") as final_file_obj:
            final_file_obj.write(final_file)
