#include "Module/SoundEngine.h"

#include "Game/Camera.h"
#include "Game/Object.h"

#include "LTE/Array.h"
#include "LTE/AutoPtr.h"
#include "LTE/Location.h"
#include "LTE/Map.h"
#include "LTE/Math.h"
#include "LTE/Pool.h"
#include "LTE/ProgramLog.h"
#include "LTE/StackFrame.h"
#include "LTE/V3.h"
#include "LTE/Vector.h"

#include "miniaudio.h"

#include <vector>

const float kDistanceScale = 50.0f;
const float kMaxDistance = 100000.0f;
const float kVelocityScale = 1.0f / 50.0f;

/* Files up to this size are decoded once and shared by every instance; larger
   ones (long ambient loops) are decoded on the fly by a decoder per instance.
   (miniaudio's own MA_SOUND_FLAG_DECODE / STREAM don't apply to data handed
   to it from memory, which is how files arrive via Location_Resource.) */
const size_t kDecodeThreshold = 1 << 20;
const String kDefaultSoundPath = "sound/";

namespace {
  /* The engine's coordinate system is left-handed (right = up x look) while
     miniaudio's is right-handed, so mirror Z on every vector we hand it. */
  V3 ToAudioSpace(V3 const& v) {
    return V3(v.x, v.y, -v.z);
  }

  struct SilentSoundImpl : public SoundT {
    void Delete() {}
    bool IsFinished() const { return true; }
    bool IsLooped() const { return false; }
    float GetDuration() const { return 1; }
    float GetPan() const { return 0; }
    float GetPitch() const { return 1; }
    float GetVolume() const { return 1; }
    void SetCursor(float position) {}
    void SetPan(float pan) {}
    void SetPitch(float pitch) {}
    void SetPlaying(bool playing) {}
    void SetVolume(float volume) {}
  };

  /* A sound file, either decoded once to shared PCM (registered with the
     resource manager under its path) or kept encoded for per-instance
     decoders. */
  struct Source {
    Array<uchar>* encoded;
    std::vector<float> pcm;
    ma_encoding_format format;

    Source() : encoded(nullptr), format(ma_encoding_format_unknown) {}
    ~Source() { delete encoded; }
  };

  /* Hint the decoder so it doesn't probe every format first. */
  ma_encoding_format FormatFromPath(String const& path) {
    size_t dot = path.rfind('.');
    String ext = dot == String::npos ? String() : String(path.substr(dot));
    if (ext == ".ogg")
      return ma_encoding_format_vorbis;
    if (ext == ".wav")
      return ma_encoding_format_wav;
    return ma_encoding_format_unknown;
  }

  struct SoundImpl : public SoundT {
    ma_sound sound;
    ma_audio_buffer* buffer;
    ma_decoder* decoder;
    /* The owning engine's registry of live sounds; null once released. */
    Vector<SoundImpl*>* live;
    float volume;
    float pan;
    float pitch;
    bool deleted;
    bool looped;

    SoundImpl() :
      buffer(nullptr),
      decoder(nullptr),
      live(nullptr),
      volume(1),
      pan(0),
      pitch(1),
      deleted(false),
      looped(false)
      {}

    ~SoundImpl() {
      Release();
    }

    void Release() {
      if (!live)
        return;
      live->remove(this);
      live = nullptr;
      ma_sound_uninit(&sound);
      if (buffer) {
        ma_audio_buffer_uninit(buffer);
        delete buffer;
        buffer = nullptr;
      }
      if (decoder) {
        ma_decoder_uninit(decoder);
        delete decoder;
        decoder = nullptr;
      }
    }

    void Delete() {
      deleted = true;
      if (live)
        ma_sound_stop(&sound);
    }

    bool IsFinished() const {
      return !live || ma_sound_at_end(&sound);
    }

    bool IsLooped() const {
      return looped;
    }

    float GetDuration() const {
      if (!live)
        return 0;

      ma_uint32 sampleRate;
      ma_uint64 length;
      ma_sound* s = (ma_sound*)&sound;
      if (ma_sound_get_data_format(s, nullptr, nullptr, &sampleRate, nullptr, 0)
            != MA_SUCCESS
          || ma_sound_get_length_in_pcm_frames(s, &length) != MA_SUCCESS
          || sampleRate == 0)
        return 0;
      return 1000.0f * (float)length / (float)sampleRate;
    }

    float GetPan() const {
      return pan;
    }

    float GetPitch() const {
      return pitch;
    }

    float GetVolume() const {
      return volume;
    }

    void SetCursor(float position) {
      if (!live) return;

      ma_uint32 sampleRate;
      ma_uint64 length;
      if (ma_sound_get_data_format(&sound, nullptr, nullptr, &sampleRate, nullptr, 0)
            != MA_SUCCESS
          || ma_sound_get_length_in_pcm_frames(&sound, &length) != MA_SUCCESS
          || length == 0)
        return;

      ma_uint64 frame = (ma_uint64)(Max(position, 0.0f) * sampleRate / 1000.0f);
      ma_sound_seek_to_pcm_frame(&sound, frame % length);
    }

    void SetPan(float pan) {
      pan = Clamp(pan, -1.0f, 1.0f);
      this->pan = pan;
      if (live)
        ma_sound_set_pan(&sound, pan);
    }

    /* Relative to the file's own sample rate, so 1 = normal speed. */
    void SetPitch(float pitch) {
      this->pitch = pitch;
      if (live)
        ma_sound_set_pitch(&sound, Max(pitch, 0.01f));
    }

    void SetPlaying(bool playing) {
      if (!live) return;
      if (playing)
        ma_sound_start(&sound);
      else
        ma_sound_stop(&sound);
    }

    void SetVolume(float volume) {
      volume = Saturate(volume);
      this->volume = volume;
      if (live)
        ma_sound_set_volume(&sound, volume);
    }
  };

  struct Sound2DInstance {
    Reference<SoundImpl> sound;
    typedef Sound2DInstance SelfType;

    POOLED_TYPE
  };

  struct Sound3DInstance {
    Reference<SoundImpl> sound;
    Object carrier;
    V3 offset;

    typedef Sound3DInstance SelfType;
    POOLED_TYPE

    void Update(V3D const& camPos) {
      V3D position = carrier
        ? (V3D)carrier->GetTransform().TransformPoint(offset)
        : (V3D)offset;

      V3 relative = ToAudioSpace((V3)(position - camPos));
      V3 velocity = ToAudioSpace(carrier
        ? kVelocityScale * carrier->GetVelocity()
        : V3(0));

      ma_sound_set_position(&sound->sound, relative.x, relative.y, relative.z);
      ma_sound_set_velocity(&sound->sound, velocity.x, velocity.y, velocity.z);
    }
  };

  struct SoundEngineMiniaudioImpl : public SoundEngine {
    ma_engine engine;
    bool initialized;
    V3D camPos;

    /* Loaded sound files by path. Null entries mark files that failed to
       load, so they're reported once and then play as silence. */
    Map<String, Source*> sources;

    Vector<SoundImpl*> live;
    Vector<Sound2DInstance*> sounds2D;
    Vector<Sound3DInstance*> sounds3D;

    SoundEngineMiniaudioImpl() :
      initialized(false),
      camPos(0)
    {
      ma_engine_config config = ma_engine_config_init();
      config.listenerCount = 1;
      if (ma_engine_init(&config, &engine) != MA_SUCCESS) {
        Log_Warning("SoundEngine (miniaudio) -- failed to initialize audio");
        return;
      }
      initialized = true;
    }

    ~SoundEngineMiniaudioImpl() {
      for (size_t i = 0; i < sounds2D.size(); ++i)
        delete sounds2D[i];
      for (size_t i = 0; i < sounds3D.size(); ++i)
        delete sounds3D[i];

      /* Sounds still referenced elsewhere outlive the engine as silent husks. */
      while (live.size())
        live.back()->Release();

      if (initialized)
        ma_engine_uninit(&engine);

      for (Map<String, Source*>::iterator it = sources.begin();
           it != sources.end(); ++it)
        delete it->second;
    }

    char const* GetName() const {
      return "SoundEngine (miniaudio)";
    }

    void Update() {
      SFRAME("Sound Engine");

      FRAME("Listener Update") {
        /* Sounds are positioned relative to the camera, so the listener
           stays at the origin. */
        Camera const& camera = Camera_Get();
        if (camera) {
          camPos = camera->GetPos();
          V3 camLook = ToAudioSpace(camera->GetLook());
          V3 camUp = ToAudioSpace(camera->GetUp());
          V3 camVelocity = ToAudioSpace(camera->GetTarget()
            ? kVelocityScale * camera->GetTarget()->GetVelocity()
            : V3(0));

          ma_engine_listener_set_position(&engine, 0, 0, 0, 0);
          ma_engine_listener_set_direction(&engine, 0, camLook.x, camLook.y, camLook.z);
          ma_engine_listener_set_world_up(&engine, 0, camUp.x, camUp.y, camUp.z);
          ma_engine_listener_set_velocity(&engine, 0,
            camVelocity.x, camVelocity.y, camVelocity.z);
        }
      }

      FRAME("2D Sound Update") {
        for (int i = 0; i < (int)sounds2D.size(); ++i) {
          Sound2DInstance* info = sounds2D[i];
          if (info->sound->IsFinished() || info->sound->deleted) {
            info->sound->deleted = false;
            delete info;
            sounds2D.removeIndex(i);
            i--;
          }
        }
      }

      FRAME("3D Sound Update") {
        for (int i = 0; i < (int)sounds3D.size(); ++i) {
          Sound3DInstance* info = sounds3D[i];
          bool carrierGone = info->carrier && info->carrier->IsDeleted();
          if (carrierGone || info->sound->IsFinished() || info->sound->deleted) {
            if (carrierGone)
              info->sound->SetPlaying(false);
            info->sound->deleted = false;
            delete info;
            sounds3D.removeIndex(i);
            i--;
            continue;
          }

          info->Update(camPos);
        }
      }
    }

    /* Load a sound file on first use. Missing or undecodable files are
       reported once and then play as silence. */
    Source* LoadSource(String const& path) {
      Source** cached = sources.get(path);
      if (cached)
        return *cached;

      sources[path] = nullptr;
      Location location = Location_Resource(path);
      if (!location->Exists()) {
        Log_Warning("SoundEngine (miniaudio) -- missing sound " + path);
        return nullptr;
      }

      AutoPtr< Array<uchar> > data = location->Read();
      if (!data) {
        Log_Warning("SoundEngine (miniaudio) -- failed to read sound " + path);
        return nullptr;
      }

      Source* source = new Source;
      source->format = FormatFromPath(path);
      if (data->size() > kDecodeThreshold) {
        source->encoded = data.t;
        data.t = nullptr;
        sources[path] = source;
        return source;
      }

      ma_decoder_config config = ma_decoder_config_init(ma_format_f32, 0, 0);
      config.encodingFormat = source->format;
      ma_decoder decoder;
      if (ma_decoder_init_memory(data->data(), data->size(), &config, &decoder)
            != MA_SUCCESS)
      {
        Log_Warning("SoundEngine (miniaudio) -- failed to decode sound " + path);
        delete source;
        return nullptr;
      }

      ma_uint32 channels = decoder.outputChannels;
      ma_uint64 frames = 0;
      ma_uint64 read = 0;
      const ma_uint64 kChunk = 16384;
      do {
        source->pcm.resize((size_t)((frames + kChunk) * channels));
        ma_decoder_read_pcm_frames(&decoder, &source->pcm[frames * channels], kChunk, &read);
        frames += read;
      } while (read == kChunk);
      source->pcm.resize((size_t)(frames * channels));
      ma_uint32 sampleRate = decoder.outputSampleRate;
      ma_decoder_uninit(&decoder);

      if (frames == 0 ||
          ma_resource_manager_register_decoded_data(
            ma_engine_get_resource_manager(&engine), path.c_str(),
            source->pcm.data(), frames, ma_format_f32, channels, sampleRate)
            != MA_SUCCESS)
      {
        Log_Warning("SoundEngine (miniaudio) -- failed to decode sound " + path);
        delete source;
        return nullptr;
      }

      sources[path] = source;
      return source;
    }

    SoundImpl* CreateSound(
      String const& file,
      bool spatialized,
      bool looped)
    {
      String path = kDefaultSoundPath + file;
      Source* source = LoadSource(path);
      if (!source)
        return nullptr;

      ma_uint32 flags = spatialized ? 0 : MA_SOUND_FLAG_NO_SPATIALIZATION;
      SoundImpl* s = new SoundImpl;
      ma_result result;

      if (source->encoded) {
        ma_decoder_config config = ma_decoder_config_init(ma_format_f32, 0, 0);
        config.encodingFormat = source->format;
        s->decoder = new ma_decoder;
        result = ma_decoder_init_memory(
          source->encoded->data(), source->encoded->size(), &config, s->decoder);
        if (result == MA_SUCCESS)
          result = ma_sound_init_from_data_source(
            &engine, s->decoder, flags, nullptr, &s->sound);
        else {
          delete s->decoder;
          s->decoder = nullptr;
        }
      } else {
        result = ma_sound_init_from_file(
          &engine, path.c_str(), flags, nullptr, nullptr, &s->sound);
      }

      if (result != MA_SUCCESS) {
        Log_Warning("SoundEngine (miniaudio) -- failed to play sound " + path);
        if (s->decoder) {
          ma_decoder_uninit(s->decoder);
          delete s->decoder;
          s->decoder = nullptr;
        }
        delete s;
        return nullptr;
      }

      s->live = &live;
      live.push(s);
      ma_sound_set_looping(&s->sound, looped);
      s->looped = looped;
      return s;
    }

    Sound Play(Array<float> const& buffer) {
      SoundImpl* s = new SoundImpl;
      ma_audio_buffer_config config = ma_audio_buffer_config_init(
        ma_format_f32, 1, buffer.size(), buffer.data(), nullptr);
      config.sampleRate = 44100;

      s->buffer = new ma_audio_buffer;
      if (ma_audio_buffer_init_copy(&config, s->buffer) != MA_SUCCESS) {
        delete s->buffer;
        s->buffer = nullptr;
        delete s;
        return new SilentSoundImpl;
      }

      if (ma_sound_init_from_data_source(&engine, s->buffer,
            MA_SOUND_FLAG_NO_SPATIALIZATION, nullptr, &s->sound) != MA_SUCCESS)
      {
        ma_audio_buffer_uninit(s->buffer);
        delete s->buffer;
        s->buffer = nullptr;
        delete s;
        return new SilentSoundImpl;
      }

      s->live = &live;
      live.push(s);

      Sound2DInstance* info = new Sound2DInstance;
      info->sound = s;
      info->sound->SetPlaying(true);
      sounds2D << info;
      return s;
    }

    Sound Play2D(String const& name, float volume, bool looped) {
      SoundImpl* s = CreateSound(name, false, looped);
      if (!s)
        return new SilentSoundImpl;

      Sound2DInstance* info = new Sound2DInstance;
      info->sound = s;
      info->sound->SetVolume(volume);
      info->sound->SetPlaying(true);
      sounds2D << info;
      return info->sound;
    }

    Sound Play3D(
      String const& name,
      Object const& carrier,
      V3 const& offset,
      float volume,
      float distanceDiv,
      bool looped)
    {
      SoundImpl* s = CreateSound(name, true, looped);
      if (!s)
        return new SilentSoundImpl;

      /* Inverse rolloff from the min distance, clamped at the max distance:
         the same model FMOD Ex used by default. */
      ma_sound_set_attenuation_model(&s->sound, ma_attenuation_model_inverse);
      ma_sound_set_min_distance(&s->sound, kDistanceScale * distanceDiv);
      ma_sound_set_max_distance(&s->sound, kMaxDistance);

      Sound3DInstance* info = new Sound3DInstance;
      info->carrier = carrier;
      info->offset = offset;
      info->sound = s;
      info->sound->SetVolume(volume);
      info->Update(camPos);
      info->sound->SetPlaying(true);
      sounds3D << info;
      return info->sound;
    }
  };
}

SoundEngine* SoundEngine_Miniaudio() {
  SoundEngineMiniaudioImpl* self = new SoundEngineMiniaudioImpl;
  if (!self->initialized) {
    delete self;
    return nullptr;
  }
  return self;
}
