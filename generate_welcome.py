import wave
import math
import struct

def generate_welcome_sound(filename):
    sample_rate = 44100
    duration = 3.5 # 3.5 seconds to match transition
    
    # Frequencies for a soothing Cmaj7 chord (C4, E4, G4, B4)
    frequencies = [261.63, 329.63, 392.00, 493.88]
    
    # Open WAV file
    wav_file = wave.open(filename, 'w')
    wav_file.setnchannels(2) # Stereo
    wav_file.setsampwidth(2) # 16-bit
    wav_file.setframerate(sample_rate)
    
    for i in range(int(sample_rate * duration)):
        t = float(i) / sample_rate
        
        # Envelope: Slow attack (1.0s), long decay
        if t < 1.0:
            env = t / 1.0
        else:
            env = max(0, 1.0 - (t - 1.0) / 2.5)
            
        # Smooth ease out
        env = env * env * (3 - 2 * env)
        
        sample_left = 0
        sample_right = 0
        
        # Mix frequencies with slight stereo detune and panning
        for idx, f in enumerate(frequencies):
            # Left channel
            val_l = math.sin(2.0 * math.pi * f * t)
            # Right channel slightly detuned
            val_r = math.sin(2.0 * math.pi * (f + 0.5) * t)
            
            # Panning and mix
            sample_left += val_l * 0.2
            sample_right += val_r * 0.2
            
        # Apply envelope and master volume
        sample_left *= env * 0.5
        sample_right *= env * 0.5
        
        # Convert to 16-bit PCM
        int_l = max(-32768, min(32767, int(sample_left * 32767.0)))
        int_r = max(-32768, min(32767, int(sample_right * 32767.0)))
        
        wav_file.writeframesraw(struct.pack('<hh', int_l, int_r))
        
    wav_file.close()

if __name__ == '__main__':
    generate_welcome_sound('/home/deck/Development/Godot/deck-store/assets/welcome.wav')
