/**
 * @file	TV1730ZLEDataObject.h
 * @brief	Data object for CAEN V1730(DPP-ZLE firmware)
 *
 * @date	Created			: 2023.01.12
 * 			Last Modified	: 2023.01.12
 * @author	Takayuki YANO
 *
 * (C) 2023 Takayuki YANO
 */

#ifndef TV1730ZLEDATAOBJECT_H
#define TV1730ZLEDATAOBJECT_H

#include <TDataObject.h>

namespace art {
	class TV1730ZLEDataObject;
}

class art::TV1730ZLEDataObject : public TDataObject {
	public:
		TV1730ZLEDataObject();
		virtual ~TV1730ZLEDataObject();
		void SetChannel(Int_t ch){ fCh = ch; }
		Int_t GetChannel() { return fCh; }
		void SetTS(ULong64_t ts) { fTS = ts; }
		ULong64_t GetTS() { return fTS; }
		void SetNumSample(Int_t numsample){ fNumSample = numsample; }
		Int_t GetNumSample() { return fNumSample; }
		virtual void Clear(const Option_t* = "");
		virtual void Copy(art::TV1730ZLEDataObject& object) const;
	protected:
		Int_t fCh;
		ULong64_t fTS;
		Int_t fNumSample;
	private:
		ClassDef(TV1730ZLEDataObject, 1);
};

#endif // TV1730ZLEDATAOBJECT_H
