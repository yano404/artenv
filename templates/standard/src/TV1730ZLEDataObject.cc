/**
 * @file	TV1730ZLEDataObject.cc
 * @brief	Data object for CAEN V1730(DPP-ZLE firmware)
 *
 * @date	Created			: 2023.01.12
 * 			Last Modified	: 2023.01.12
 * @author	Takayuki YANO
 *
 * (C) 2023 Takayuki YANO
 */

#include "TV1730ZLEDataObject.h"

art::TV1730ZLEDataObject::TV1730ZLEDataObject(): fCh(0), fTS(0), fNumSample(0)
{
}

art::TV1730ZLEDataObject::~TV1730ZLEDataObject() {
}

void art::TV1730ZLEDataObject::Clear(Option_t *) {
	fTS = 0;
	fNumSample = 0;
	fNumSample = 0;
}

void art::TV1730ZLEDataObject::Copy(art::TV1730ZLEDataObject &object) const {
	art::TV1730ZLEDataObject &obj = *(art::TV1730ZLEDataObject*)&object;
	obj.fCh = fCh;
	obj.fTS = fTS;
	obj.fNumSample = fNumSample;
	art::TDataObject::Copy(obj);
}
