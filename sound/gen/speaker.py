"""柱のスピーカーを通した曲。

music_speaker_loop  柱が出す音（Godot はこれを鳴らす）。ラッパ型: 300 Hz〜3.5 kHz、1 kHz の張り出し、
                    2.5 kHz の鼻にかかった癖、小さなアンプの歪み
music_speaker_far   確かめ用。2 本の柱（20 m と 50 m）の間に立って聞いた形。距離で遅れと高い音の減り、
                    風のうねり。Godot 側の処理の目安で、ゲームでは使わない
"""
import numpy as np
from scipy.io import wavfile

from lib import SR, WAV, db, hp, lp, n_of, normalize, peak_eq, slow_random, softclip, write

C_SOUND = 340.0


def horn(x):
    y = hp(x, 300, 4)
    y = lp(y, 3500, 4)
    y = peak_eq(y, 1000, 6, 1.0)
    y = peak_eq(y, 2500, 5, 3.0)
    y = normalize(y, -6)
    y = softclip(y * 2.2, 2.0)
    y = lp(y, 4200, 2)
    return y


def far_pass(x, dist, rng, wind_hz):
    """距離 dist m の柱から届く形。雪と空気で高い音が先に細り、風で音量がうねる"""
    fc = np.interp(dist, [0, 20, 60, 100], [4000, 3000, 2000, 1500])
    y = lp(x, fc, 2)
    gain = db(-20 * np.log10(max(dist, 1.0) / 5.0))   # 5 m を 0 dB に
    n = len(y)
    sway = db(3.5 * slow_random(n, wind_hz, rng))
    y = y * gain * sway
    delay = n_of(dist / C_SOUND)
    return np.concatenate([np.zeros(delay), y])


if __name__ == "__main__":
    sr, raw = wavfile.read(WAV / "music_loop.wav")
    dry = raw.astype(np.float64) / 32767
    # フィルタはループの頭と尾をつないだままかける（3 回つないで真ん中を取る）。でないと継ぎ目に段差が出る
    n = len(dry)
    post = write("music_speaker_loop.wav", horn(np.tile(dry, 3))[n:2 * n], -3)

    rng = np.random.default_rng(1100)
    two = np.tile(post, 2)   # 30 s
    a = far_pass(two, 20, rng, 0.07)
    b = far_pass(two, 50, rng, 0.11)
    n = max(len(a), len(b))
    mix = np.zeros(n)
    mix[:len(a)] += a
    mix[:len(b)] += b
    write("music_speaker_far.wav", mix[:n_of(30)], -6)
