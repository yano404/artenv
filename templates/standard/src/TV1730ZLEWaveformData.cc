/**
 * @file	TV1730ZLEWaveformData.cc
 * @brief	Waveform data store for CAEN V1730(DPP-ZLE firmware)
 *
 * @date	Created			: 2023.01.04
 * 			Last Modified	: 2023.01.11
 * @author	Takayuki YANO
 *
 * (C) 2023 Takayuki YANO
 */

#include "TV1730ZLEWaveformData.h"

art::TV1730ZLEWaveformData::TV1730ZLEWaveformData(): fADC(NULL), fTimeBacket(NULL), fZeroSuppressed(NULL)
{
	fADC = new UShort_t[kMaxSample];
	fTimeBacket = new UShort_t[kMaxSample];
	fZeroSuppressed = new Int_t[kMaxSample];
}

art::TV1730ZLEWaveformData::~TV1730ZLEWaveformData() {
	if (fADC) {
		delete fADC;
		fADC = 0;
	}
	if (fTimeBacket) {
		delete fTimeBacket;
	}
	if (fZeroSuppressed) {
		delete fZeroSuppressed;
	}
}

UShort_t art::TV1730ZLEWaveformData::GetSample(int idx) {
	return fADC[idx];
}

UShort_t art::TV1730ZLEWaveformData::GetTimeBacket(int idx) {
	return fTimeBacket[idx];
}

Int_t art::TV1730ZLEWaveformData::IsZeroSuppressed(int idx) {
	return fZeroSuppressed[idx];
}

UShort_t &art::TV1730ZLEWaveformData::operator[] (int idx) {
	return fADC[idx];
}

UShort_t &art::TV1730ZLEWaveformData::operator() (int idx) {
	return fTimeBacket[idx];
}

void art::TV1730ZLEWaveformData::AddSample(Int_t isample, UShort_t tb, UShort_t fadcval) {
	if (fadcval == fSkippedSampleValue) {
		fADC[isample] = fadcval;
		fTimeBacket[isample] = tb;
		fZeroSuppressed[isample] = 1;
	} else {
		fADC[isample] = fadcval;
		fTimeBacket[isample] = tb;
		fZeroSuppressed[isample] = 0;
	}
}

void art::TV1730ZLEWaveformData::Clear(Option_t *) {
	fNumSample = 0;
}

void art::TV1730ZLEWaveformData::Copy(art::TV1730ZLEWaveformData &object) const {
	art::TV1730ZLEWaveformData &obj = *(art::TV1730ZLEWaveformData*)&object;
	obj.fNumSample = fNumSample;
	for (Int_t i=0; i<fNumSample; i++) {
		obj.fADC[i] = fADC[i];
		obj.fTimeBacket[i] = fTimeBacket[i];
		obj.fZeroSuppressed[i] = fZeroSuppressed[i];
	}
	art::TV1730ZLEDataObject::Copy(obj);
}
