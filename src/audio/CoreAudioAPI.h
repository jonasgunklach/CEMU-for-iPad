#pragma once

#include "IAudioAPI.h"

#include <AudioToolbox/AudioToolbox.h>

// RemoteIO based audio output, used on iPadOS where cubeb's AudioUnit backend is unavailable
class CoreAudioAPI : public IAudioAPI
{
public:
	class CoreAudioDeviceDescription : public DeviceDescription
	{
	public:
		CoreAudioDeviceDescription()
			: DeviceDescription(L"Default") { }

		std::wstring GetIdentifier() const override { return L"default"; }
	};

	CoreAudioAPI(uint32 samplerate, uint32 channels, uint32 samples_per_block, uint32 bits_per_sample);
	~CoreAudioAPI() override;

	AudioAPI GetType() const override { return CoreAudio; }
	bool NeedAdditionalBlocks() const override;
	bool FeedBlock(sint16* data) override;
	bool Play() override;
	bool Stop() override;
	void SetVolume(sint32 volume) override;

	static std::vector<DeviceDescriptionPtr> GetDevices();
	static bool InitializeStatic() { return true; }

private:
	static OSStatus RenderCallback(void* userData, AudioUnitRenderActionFlags* flags, const AudioTimeStamp* timeStamp, UInt32 busNumber, UInt32 frameCount, AudioBufferList* data);

	AudioComponentInstance m_unit = nullptr;
	bool m_isPlaying = false;
	std::atomic<float> m_volumeScale = 1.0f;

	mutable std::shared_mutex m_mutex;
	std::vector<uint8> m_buffer;
};
