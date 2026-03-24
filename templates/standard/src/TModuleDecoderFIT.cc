/*
 * @file TModuleDecoderFIT.cc
 * @date  Created : 2024.09.08 (T.Yano)
 *  Last Modified : 2024.09.08 (T.Yano)
 */
#include "TModuleDecoderFIT.h"
#include <TRawTimingWithEdge.h>
#include <TObjArray.h>

using art::TModuleDecoderFIT;
using art::TRawTimingWithEdge;

typedef TRawTimingWithEdge FITRaw_t;

ClassImp(TModuleDecoderFIT)

TModuleDecoderFIT::TModuleDecoderFIT()
  : TModuleDecoder(kID, FITRaw_t::Class()) {
  fHitData = new TObjArray;
}

TModuleDecoderFIT::TModuleDecoderFIT(Int_t id)
  : TModuleDecoder(id, FITRaw_t::Class()) {
  fHitData = new TObjArray;
}

TModuleDecoderFIT::~TModuleDecoderFIT()
{
  if (fHitData) delete fHitData;
  fHitData = NULL;
}

Int_t TModuleDecoderFIT::Decode(char* buf, const int &size, TObjArray *seg)
{
  UInt_t *evtdata = (UInt_t*) buf;
  UInt_t evtsize = size/sizeof(UInt_t);
  Int_t igeo;
  Int_t err, trg, edge, ch, measure;
  
  fHitData->Clear();

  // Structure of 1st word
  // bits
  //  0-11 : geometry
  // 12-27 : trigger number
  // 28-31 : 0b0110

  // Read geometry
  igeo = evtdata[0] & 0x0fff;

  // 2nd word ~ : Hits
  // Structure of hits
  // bits 
  //  0-19 : data.
  // 20-27 : channel.
  //       :   0- 63 = leading edge
  //       :      64 = trigger
  //       :  68- 70 = timestamp (currently not used)
  //       : 128-191 = trailing edge
  //    28 : trigger. (currently not used)
  // 29-30 : fixed to 0.
  //    31 : error.
 
  for(size_t i{1}; i != evtsize; i ++) {
    err     = (evtdata[i] & 0x80000000) >> 31; // err bit
    if (err) continue;
    trg     = (evtdata[i] & 0x10000000) >> 28; // trigger
    edge    = (evtdata[i] & 0x08000000) >> 27; // edge (0:leading, 1:trailing)
    ch      = (evtdata[i] & 0x07f00000) >> 20; // channel
    measure = (evtdata[i] & 0x00fffff); // data

    if (fHitData->GetEntriesFast() <= ch || !fHitData->At(ch)) {
      // if no data object is available, create one
      auto obj = static_cast<FITRaw_t*>(this->New());
      obj->SetSegInfo(seg->GetUniqueID(), igeo, ch);
      fHitData->AddAtAndExpand(obj, ch);
      seg->Add(obj);
    }

    auto data = static_cast<FITRaw_t*>(fHitData->At(ch));
    data->Set(measure);
    data->SetEdge(!edge); // (0:trailing, 1:leading) in TRawTimingWithEdge
    fHitData->AddAt(NULL,ch);
  }

  return 0;
}
