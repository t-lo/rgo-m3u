#!/usr/bin/gawk
#
# Copyright (c) 2024 Thilo Fromm
# Use of this source code is governed by the Apache 2.0 license.
#
# Rebel Galaxy / RG Outlaw M3U generator
# This AWK script generates a randomised playlist from the RG:O soundtrack.
# It switches radio stations randomly and ensures stations' DJs tune in every now and then.
# It also mixes in RGO's famous fun advertisements.
# Optionally, the script mixes in the original Rebel Galaxy soundtrack as separate "stations".
#
# Example usage:
# find RebelGalaxyOST/ RebelGalaxyOutlawOST -print | gawk -f mkm3u.awk > rebel_galaxy_all.m3u8x

BEGIN {
  urand = "tr -dc '[:alnum:]' </dev/urandom | head -c 6"
  urand | getline rnd
  close(urand)
  srand(rnd)
  split("", ads)
  split("", stations)
}
# --

#
# File name matching / array filling
#

# Append a file name to an array. Since the initial length is 0, items start at
# index 0.
function append_and_next(array, subidx, subsub,       l) {
  if (subsub) {
    l = length(array[subidx][subsub])
    array[subidx][subsub][l] = $0
  } else if (subidx) {
    l = length(array[subidx])
    array[subidx][l] = $0
  } else {
    l = length(array)
    array[l] = $0
  }
  next
}
# --

function init_station(chan,                  i, j) {
  if(stations[chan])
    return

  tracks[chan]["dummy"] = "dummy"; delete tracks[chan]["dummy"]

  split("dj pretrack posttrack stinger", i)
  for (j in i) {
    interloops[chan][i[j]]["dummy"] = "dummy"
    delete interloops[chan][i[j]]["dummy"]
  }

  stations[chan]=1
}
# --

function tracks_count(      i, c) {
  for (i in tracks)
    c = c + length(tracks[i])

  return c
}
# --

{
  # filter non-track files and directories
  if (0 == index($0, ".ogg"))
    next

  # RG
  if (0 != index($0, "RebelGalaxy-orig")) {
    if (match($0, ".*_inst.ogg"))
      chan="RebelGalaxy-instrumental"
    else if (match($0, ".*_light.ogg"))
      chan="RebelGalaxy-light"
    else
      chan="RebelGalaxy"
    init_station(chan)
    append_and_next(tracks, chan)
  }

  # handle commercials and soundtrack first
  if (0 != index($0, "COMMERCIAL")) {
    append_and_next(ads, "")
  }

  # RG:O soundtrack / ambient
  if (0 != index($0, "SOUNDTRACK")) {
    chan=gensub(".*SOUNDTRACK/([A-Z]+)/.*","\\1","1")
    chan="soundtrack-" chan
    init_station(chan)
    append_and_next(tracks, chan)
  }

  # handle stations
  chan=gensub(".*RADIO/([A-Z]+)/.*","\\1","1")
  init_station(chan)

  # filter DJs, stations
  if (match($0, "_dj[0-9a-z]+\\.ogg"))
    append_and_next(interloops, chan, "dj")
  if (match($0, "_pretrack[0-9a-z]+\\.ogg"))
    append_and_next(interloops, chan, "pretrack")
  if (match($0, "_posttrack[0-9a-z]+\\.ogg"))
    append_and_next(interloops, chan, "posttrack")
  if (match($0, "stinger[0-9a-z]+\\.ogg"))
    append_and_next(interloops, chan, "stinger")

  append_and_next(tracks, chan)
}
# --

#
# Print randomised tracks, DJ announcements, and ads list
#
# Remove one random element from array, return element.
# Note that AWK arrays are associative, so deleting the Nth element needs some
# housekeeping.
function pop_rnd(array,      l,i,e) {
  l = length(array)
  i = int(rand() * l)
  for (e in array) {
    l = l - 1
    if (i == l) {
      i = e
      e = array[i]
      delete array[i]
      break
    }
  }
  return e
}
# --

function print_stats(array, name,     e) {
  print "# " name " : " length(array) " entries"
#  for (e in array)
#    print "#   " array[e]

}
# --

#
# Print stats and generate playist
#
function banner(message,                 l, p) {
  l=length(message)
  while (l>0) {
    p = p "#"
    l = l-1
  }
  print "#\n#"
  print "#                   ###" p "###"
  print "#                   #  " message "  #"
  print "#                   ###" p "###"
}
# --

function update_stations_weights(                   s, num_tracks) {
  print "# ----"
  print "# Station weights"
  print "# ----"
  num_tracks = tracks_count()
  for (s in stations) {
    if (length(tracks[s]))
      station_weights[s] = length(tracks[s]) / num_tracks
    else
      station_weights[s] = 0
    print "#   " s " : " station_weights[s]
  }
  print "# ----"
}
# --

function pick_random_station(old_station,                 c, s, w) {
  c = rand()
  for (s in stations) {
    if ((s != old_station) && \
        (w + station_weights[s] >= c) && \
        (0 < length(tracks[s])) )
        return s
    w = w + station_weights[s]
  }
  return station
}
# --

function update_station_interloop_weights(station,     i, all_inter) {
  for (i in interloops[station]) {
    all_inter = all_inter + length(interloops[station][i])
  }

  print "# tracks count: " length(tracks[station])
  print "# all interloops count: " all_inter

  if (0 == all_inter)
      return

  for (i in interloops[station]) {
    interloop_chances[station][i] = \
      length(interloops[station][i]) / all_inter
    print "# interloop '" i "' count " length(interloops[station][i]) \
      " weight " interloop_chances[station][i]
  }
}
# --

function chance_switch_stations(chance, station,     i, j) {
  if ((station != "") && (rand() > chance))
    return station

  banner("Switchting stations")
  print "# Previous station: '" station "', switch chance was " chance
  update_stations_weights()
  old_station=station
  station = pick_random_station(station)
  if (old_station == station)
  if ("" == station) {
    print "# No tracks left on any station"
    return
  }

  print "# New station: '" station "'"

  update_station_interloop_weights(station)

  split("stinger dj pretrack", i)
  for (j in i)
    if (length(interloops[station][i[j]])) {
      print pop_rnd(interloops[station][i[j]])
      break
    }

  return station
}
# --

function chance_play_interloop(station, type, tracks_since_interloop,     c, i) {
  if (tracks_since_interloop < 1)
    return tracks_since_interloop

  if(0 == length(interloops[station][type]))
    return tracks_since_interloop

  for (i in interloops[station])
    c = c + length(interloops[station][i])

  if (rand() > (c*tracks_since_interloop / ( length(tracks[station])+1 )) )
    return tracks_since_interloop

  if (rand() > interloop_chances[station][type])
    return tracks_since_interloop 

  print "# interloop '" type "'"
  print pop_rnd(interloops[station][type])
  return 0
}
# --

function chance_play_ad(last_ad_at) {
  if (0 == length(ads))
   return last_ad_at
  if (rand() > ((last_ad_at - tracks_count()) / 15))
   return last_ad_at

  print "# and now a word from our sponsors"
  print ads[int(rand() * length(ads))]
  return tracks_count()
}
# --

END {
  switch_min = 3
  switch_max = 7

  print "#EXTM3U"
  banner("Playlist stations data")
  print_stats(ads, "Ads")
  for (s in stations) {
    print "#\n# ----"
    print "# Station " s
    print "# ----"
    update_station_interloop_weights(s)
  }

  station = chance_switch_stations(chance_switch, "")
  track_count=0
  tracks_since_interloop=0
  last_ad_at=tracks_count()
  while (1) {
    tracks_since_interloop = chance_play_interloop(station, "dj", tracks_since_interloop)
    tracks_since_interloop = chance_play_interloop(station, "pretrack", tracks_since_interloop)

    print pop_rnd(tracks[station])
    if (0 == tracks_count())
      break
    track_count = track_count + 1
    tracks_since_interloop = tracks_since_interloop + 1

    last_ad_at=chance_play_ad(last_ad_at)

    tracks_since_interloop = chance_play_interloop(station, "posttrack", tracks_since_interloop)
    tracks_since_interloop = chance_play_interloop(station, "stinger", tracks_since_interloop)

    if ((0 == length(tracks[station])) || (track_count >= switch_min)) {
      old_station = station
      if ( (track_count >= switch_max) || (0 == length(tracks[station])) )
        chance = 1
      else
        chance = ((tracks_count() / length(tracks)) * 0.7) / length(tracks[station])
      station = chance_switch_stations(chance, station)
      if (old_station != station) {
        track_count = 0
        tracks_since_interloop = 0
      }
    }
  }

  banner("ALL DONE")
  print "# Final interloops count"
  for (station in interloops) {
    print "# --- station " station " ---"
    for (i in interloops[station])
      print "#  " i " : " length(interloops[station][i])
  }
}
