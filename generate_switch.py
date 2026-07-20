import wave
import math
import struct
import random

def generate_switch_sound(filename):
    sample_rate = 44100
    duration = 0.2 # 200ms sound
    
    wav_file = wave.open(filename, 'w')
    wav_file.setnchannels(2)
    wav_file.setsampwidth(2)
    wav_file.setframerate(sample_rate)
    
    filtered_noise = 0.0
    for i in range(int(sample_rate * duration)):
        t = float(i) / sample_rate
        
        # Quick attack, smooth decay
        if t < 0.02:
            env = t / 0.02
        else:
            env = math.exp(-(t - 0.02) * 25.0)
            
        noise = random.uniform(-1.0, 1.0)
        # Simple low pass filter
        filtered_noise += (noise - filtered_noise) * 0.05
        
        # Soft low-mid frequency tone for warmth
        freq = 200.0 * math.exp(-t * 10.0)
        tone = math.sin(2.0 * math.pi * freq * t)
        
        # Mix tone and filtered noise
        sample = (filtered_noise * 0.6 + tone * 0.4) * env * 0.6
        
        int_val = max(-32768, min(32767, int(sample * 32767.0)))
        
        wav_file.writeframesraw(struct.pack('<hh', int_val, int_val))
        
    wav_file.close()

if __name__ == '__main__':
    generate_switch_sound('/home/deck/Development/Godot/deck-store/assets/switch.wav')
