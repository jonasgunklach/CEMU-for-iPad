#include "CoreAudioAPI.h"

CoreAudioAPI::CoreAudioAPI(uint32 samplerate, uint32 channels, uint32 samples_per_block, uint32 bits_per_sample)
	: IAudioAPI(samplerate, channels, samples_per_block, bits_per_sample)
{
	cemu_assert(bits_per_sample == 16);

	AudioComponentDescription desc{};
	desc.componentType = kAudioUnitType_Output;
	desc.componentSubType = kAudioUnitSubType_RemoteIO;
	desc.componentManufacturer = kAudioUnitManufacturer_Apple;

	AudioComponent component = AudioComponentFindNext(nullptr, &desc);
	if (!component || AudioComponentInstanceNew(component, &m_unit) != noErr)
		throw std::runtime_error("can't create RemoteIO audio unit");

	AudioStreamBasicDescription format{};
	format.mSampleRate = samplerate;
	format.mFormatID = kAudioFormatLinearPCM;
	format.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
	format.mChannelsPerFrame = channels;
	format.mBitsPerChannel = bits_per_sample;
	format.mBytesPerFrame = channels * (bits_per_sample / 8);
	format.mFramesPerPacket = 1;
	format.mBytesPerPacket = format.mBytesPerFrame;

	AURenderCallbackStruct callback{};
	callback.inputProc = RenderCallback;
	callback.inputProcRefCon = this;

	if (AudioUnitSetProperty(m_unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &format, sizeof(format)) != noErr ||
		AudioUnitSetProperty(m_unit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &callback, sizeof(callback)) != noErr ||
		AudioUnitInitialize(m_unit) != noErr)
	{
		AudioComponentInstanceDispose(m_unit);
		m_unit = nullptr;
		throw std::runtime_error("can't initialize RemoteIO audio unit");
	}

	m_buffer.reserve((size_t)m_bytesPerBlock * kBlockCount);
}

CoreAudioAPI::~CoreAudioAPI()
{
	if (m_unit)
	{
		Stop();
		AudioUnitUninitialize(m_unit);
		AudioComponentInstanceDispose(m_unit);
	}
}

OSStatus CoreAudioAPI::RenderCallback(void* userData, AudioUnitRenderActionFlags* flags, const AudioTimeStamp* timeStamp, UInt32 busNumber, UInt32 frameCount, AudioBufferList* data)
{
	auto* thisptr = (CoreAudioAPI*)userData;
	auto* output = (uint8*)data->mBuffers[0].mData;
	const size_t size = std::min<size_t>(data->mBuffers[0].mDataByteSize, (size_t)frameCount * thisptr->m_channels * (thisptr->m_bitsPerSample / 8));

	size_t copied;
	{
		std::unique_lock lock(thisptr->m_mutex);
		copied = std::min(thisptr->m_buffer.size(), size);
		memcpy(output, thisptr->m_buffer.data(), copied);
		thisptr->m_buffer.erase(thisptr->m_buffer.begin(), std::next(thisptr->m_buffer.begin(), copied));
	}
	// fill rest with silence
	if (copied != size)
		memset(output + copied, 0x00, size - copied);

	const float volume = thisptr->m_volumeScale.load(std::memory_order_relaxed);
	if (volume < 1.0f)
	{
		auto* samples = (sint16*)output;
		for (size_t i = 0; i < copied / sizeof(sint16); i++)
			samples[i] = (sint16)((float)samples[i] * volume);
	}
	return noErr;
}

bool CoreAudioAPI::NeedAdditionalBlocks() const
{
	std::shared_lock lock(m_mutex);
	return m_buffer.size() < GetAudioDelay() * m_bytesPerBlock;
}

bool CoreAudioAPI::FeedBlock(sint16* data)
{
	std::unique_lock lock(m_mutex);
	if (m_buffer.capacity() <= m_buffer.size() + m_bytesPerBlock)
	{
		cemuLog_logDebug(LogType::Force, "dropped CoreAudio block since too many buffers are queued");
		return false;
	}
	m_buffer.insert(m_buffer.end(), (uint8*)data, (uint8*)data + m_bytesPerBlock);
	return true;
}

bool CoreAudioAPI::Play()
{
	if (m_isPlaying)
		return true;
	m_isPlaying = AudioOutputUnitStart(m_unit) == noErr;
	return m_isPlaying;
}

bool CoreAudioAPI::Stop()
{
	if (!m_isPlaying)
		return true;
	if (AudioOutputUnitStop(m_unit) != noErr)
		return false;
	m_isPlaying = false;
	return true;
}

void CoreAudioAPI::SetVolume(sint32 volume)
{
	IAudioAPI::SetVolume(volume);
	m_volumeScale = (float)volume / 100.0f;
}

std::vector<IAudioAPI::DeviceDescriptionPtr> CoreAudioAPI::GetDevices()
{
	// iPadOS routes audio itself (speaker, headphones, AirPlay, ...)
	return {std::make_shared<CoreAudioDeviceDescription>()};
}
