/**
 * @file	TV1730ZLEWaveformData.h
 * @brief	Waveform data store for CAEN V1730(DPP-ZLE firmware)
 *
 * @date	Created			: 2023.01.12
 * 			Last Modified	: 2023.01.12
 * @author	Takayuki YANO
 *
 * (C) 2023 Takayuki YANO
 */

#ifndef TV1730ZLEWAVEFORMDATA_H
#define TV1730ZLEWAVEFORMDATA_H

#include "TV1730ZLEDataObject.h"

namespace art {
	class TV1730ZLEWaveformData;
}

class art::TV1730ZLEWaveformData : public TV1730ZLEDataObject {
	public:
		TV1730ZLEWaveformData();
		~TV1730ZLEWaveformData();
		UShort_t GetSample(int idx);
		UShort_t GetTimeBacket(int idx);
		Int_t IsZeroSuppressed(int idx);
		UShort_t &operator[] (int idx);
		UShort_t &operator() (int idx);
		void AddSample(Int_t isample, UShort_t tb, UShort_t fadcval);
		virtual void Clear(const Option_t* = "");
		virtual void Copy(art::TV1730ZLEWaveformData& object) const;
	protected:
		static const int kMaxSample = 10000;
		static const UShort_t fSkippedSampleValue = 20000;
		UShort_t *fADC; // [fNumSample]
		UShort_t *fTimeBacket; // [fNumSample]
		Int_t *fZeroSuppressed; // [fNumSample]
	private:
		ClassDef(TV1730ZLEWaveformData, 1);
};

#endif // TV1730ZLEWAVEFORMDATA_H
