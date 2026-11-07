#!/usr/bin/env python3
"""Original 96s ambient loop 'Quiet Garden', no samples or external music.

60 BPM, D major / B minor, 24 bars. Low felt-like tones, restrained overtones,
warm slow pads. Circular mixing carries note and reverb tails over the seam.
Python standard library + ffmpeg (Vorbis encoder). WAV master in build/music/.
"""
from array import array
import json
import math
from pathlib import Path
import subprocess
import wave

ROOT=Path(__file__).resolve().parents[1]
SR=44100
DURATION=96
N=SR*DURATION
TAU=math.tau

def main():
    left=array('d',[0])*N
    right=array('d',[0])*N
    cache={}
    score=[]
    def note(start,midi,kind,gain,pan):
        key=(midi,kind)
        if key not in cache:
            freq=440*2**((midi-69)/12)
            length=8 if kind=='pad' else 6
            voice=array('d')
            for i in range(length*SR):
                sec=i/SR
                if kind=='pad':
                    env=math.sin(math.pi*sec/length)**2
                    value=(math.sin(TAU*freq*sec)+.22*math.sin(TAU*2*freq*sec)+.08*math.sin(TAU*3*freq*sec))/1.3
                else:
                    env=(1-math.exp(-sec/0.16))*math.exp(-sec/1.8)*(1-sec/length)**2
                    value=(math.sin(TAU*freq*sec)+.08*math.sin(TAU*2*freq*sec)*math.exp(-sec/0.6)+.015*math.sin(TAU*3*freq*sec)*math.exp(-sec/.25))
                voice.append(env*value)
            cache[key]=voice
        gl=gain*math.sqrt((1-pan)/2)
        gr=gain*math.sqrt((1+pan)/2)
        start_i=round(start*SR)
        for i,v in enumerate(cache[key]):
            j=(start_i+i)%N
            left[j]+=v*gl
            right[j]+=v*gr
        score.append(dict(beat=start,midi=midi,instrument=kind,gain=gain,pan=pan))
    # Dadd9, Bm7, Gmaj9, Asus4/add9. Common tones keep the cycle unhurried.
    chords=[[50,57,64,66],[47,54,57,62],[43,54,57,62],[45,52,59,62]]
    melodies=[[74,78,76],[73,69,74],[71,74,78],[76,71,69],
              [78,81,76],[74,73,69],[71,78,74],[76,74,69]]
    for bar in range(24):
        start=bar*4
        chord=chords[bar%4]
        for j,pitch in enumerate(chord):
            note(start-2,pitch,'pad',.048 if j==0 else .026,(j-1.5)*.22)
        phrase=melodies[bar%8]
        for j,pitch in enumerate(phrase):
            # Leave regular breathing spaces; no percussion or high bright ticks.
            if bar%8 in [3,7] and j==2: continue
            note(start+[.35,1.75,2.9][j],pitch-12,'pluck',.075 if j==0 else .055,[-.24,.22,.05][j])
        if bar%2==0:
            note(start+2.2,chord[1],'pluck',.03,-.35)
    # Circular stereo reflections, each tap uses the dry signal (no runaway feedback).
    dry_l=array('d',left); dry_r=array('d',right)
    for delay,gain in [(.173,.21),(.379,.16),(.617,.12),(.929,.085),(1.387,.055),(2.113,.035)]:
        shift=round(delay*SR)
        for i in range(N):
            src=(i-shift)%N
            left[i]+=dry_r[src]*gain
            right[i]+=dry_l[src]*gain
    peak=max(max(map(abs,left)),max(map(abs,right)))
    gain=.40/peak
    pcm=array('h')
    for l,r in zip(left,right): pcm.extend((round(l*gain*32767),round(r*gain*32767)))
    master=ROOT/'build/music/quiet-garden.wav'
    master.parent.mkdir(parents=True,exist_ok=True)
    with wave.open(str(master),'wb') as f:
        f.setnchannels(2); f.setsampwidth(2); f.setframerate(SR); f.writeframes(pcm.tobytes())
    out=ROOT/'assets/music'
    out.mkdir(parents=True,exist_ok=True)
    subprocess.run(['ffmpeg','-v','error','-y','-i',str(master),'-c:a','vorbis','-strict','experimental','-q:a','4',str(out/'quiet-garden.ogg')],check=True)
    rms=math.sqrt(sum((v/32768)**2 for v in pcm)/len(pcm))
    report=dict(title='Quiet Garden',duration_seconds=DURATION,bpm=60,bars=24,
        sample_rate=SR,channels=2,peak_dbfs=20*math.log10(.40),rms_dbfs=20*math.log10(rms),
        seam_step=[abs(left[0]-left[-1])*gain,abs(right[0]-right[-1])*gain],
        provenance='Original deterministic synthesis; no samples; tools/compose-garden.py',score=score)
    (out/'score.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({k:v for k,v in report.items() if k!='score'},indent=2))

if __name__=='__main__': main()
