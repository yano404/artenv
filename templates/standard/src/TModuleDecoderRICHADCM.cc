/*
 * @file TModuleDecoderRICHADCM.cc
 * @date  Created : 2022.07.14 HJKT
 *  Last Modified : 2022.07.15 BB
 *--------------------------------------------------------
 *    Comment : Si trb decoder for ridf format 
 *              original : TArtDecoderRICHADCM.cc by H. Baba
 *
 *--------------------------------------------------------
 *    Copyright (C) by Yuto HIJIKATA
 */
#include "TModuleDecoderRICHADCM.h"
#include <TRawDataSimple.h>
#include <TObjArray.h>

using art::TModuleDecoderRICHADCM;
using art::TRawDataSimple;

typedef TRawDataSimple<UInt_t> RICHADCMRaw_t;

ClassImp(TModuleDecoderRICHADCM)

TModuleDecoderRICHADCM::TModuleDecoderRICHADCM()
: TModuleDecoder(kID,RICHADCMRaw_t::Class()) {
  fHitData = new TObjArray;
}

TModuleDecoderRICHADCM::TModuleDecoderRICHADCM(Int_t id, EChannelNumberingMode mode)
  : TModuleDecoder(id,RICHADCMRaw_t::Class()), fChMode{mode} {
  fHitData = new TObjArray;
}

TModuleDecoderRICHADCM::~TModuleDecoderRICHADCM()
{
  if (fHitData) delete fHitData;
  fHitData = NULL;
}

Int_t TModuleDecoderRICHADCM::Endian(UInt_t x)
{
  return ((x & 0x000000ff) << 24)
    |    ((x & 0x0000ff00) << 8)
    |    ((x & 0x00ff0000) >> 8)
    |    ((x & 0xff000000) >> 24);
}

Int_t TModuleDecoderRICHADCM::Decode(char* buf, const int &size, TObjArray *seg)
{
  UInt_t *evtdata = (UInt_t*) buf;
  UInt_t evtsize = size/sizeof(UInt_t);
  RICHADCMRaw_t *data;

  /*
  enum EvtIdx {
	EvtIdx_size,
	EvtIdx_decoding,
	EvtIdx_id,
	EvtIdx_seqNr,
	EvtIdx_date,
	EvtIdx_time,
	EvtIdx_runNr,
	EvtIdx_expId,
	EvtIdx_data
	};

  enum SubEvtIdx {
	SubEvtIdx_size,
	SubEvtIdx_decoding,
	SubEvtIdx_id,
	SubEvtIdx_trigNr,
	SubEvtIdx_data
	};

  d_dataWord = word;
  d_adcVal   = (word >>  0) & 0x3fff;
  d_channel  = (word >> 14) & 0x007f;
  d_apv      = (word >> 21) & 0x000f;
  d_adcm     = (word >> 25) & 0x0007;
  d_sector   = (word >> 28) & 0x0007;

  */

  if(size < 64){
    Info(__FILE__,"** NO APV data size=%d ****  \n", size);
    return 0;
  }

  /*  for(int i{}; i != evtsize; ++i) {
    printf("%08x ", evtdata[i]);
    if(i % 8 == 7) printf("\n");
  }
  printf("\n");*/
  
  // evtheader size = 8 x 32bit
  Int_t evtid = evtdata[2];
  //  printf("evtid: %x, evtsize: %d\n", evtid, evtsize);
  
  // evtdata index = 8
  Int_t subevtid = Endian(evtdata[10]);
  Int_t subevtsize = Endian(evtdata[8]); // subevtsize in char
  Int_t trignr = Endian(evtdata[11]); // subevtsize in char
  //  printf("subevtid, subevtsize, trignr: %x, %x, %x\n", subevtid, subevtsize, trignr);
  
  // if start_acq / stop_acq header is included, data sequence might be shifted
  switch(evtid) {
    case 0x00010002:
      Info(__FILE__,"EvtID = START_ACQ 0x%08x\n", evtid);
      return 0;
    case 0x00010003:
      Info(__FILE__,"EvtID = STOP_ACQ 0x%08x\n", evtid);
      return 0;
  }

  // actual apv data size (int unit)
  Int_t apvsize = (Endian(evtdata[12]) & 0xffff0000) >> 16;

  if(apvsize > size-14){
    Info(__FILE__,"  ** invalid APV size %d (size=%d) ****  \n", apvsize, size);
    return 0;
  }
  
  // clear old hits
  fHitData->Clear();

  //  printf("apvsize: %d\n",apvsize);
  
  int off=14;
  int datanum = 0;
  int dataidx = 0;
  for (int i{}; i != apvsize; ++i) {
    Int_t z = Endian(evtdata[i+13]);

     if(!datanum){
       dataidx = 0;
       datanum = (z >> 16) & 0x0000ffff;
       continue;
     }

    Int_t adcVal   = (z & 0x00003fff);
    Int_t channel  = (z & 0x001fc000) >> 14; // (z >> 14) & 0x007f;
    Int_t apv      = (z & 0x01e00000) >> 21; // (z >> 21) & 0x000f;
    Int_t adcm     = (z & 0x0e000000) >> 25; // (z >> 25) & 0x0007;
    Int_t sector   = (z & 0x70000000) >> 28; // (z >> 28) & 0x0007;
    Int_t dbflag   = (z & 0x80000000) >> 31; // (z >> 31) & 0x0001; // flag of debug/status

    //    printf("sec, adcm, ch, value, dbflag: %d, %d, %d, %d, %d\n", sector, adcm, channel, adcVal, dbflag);
    
    if(dbflag == 1){
       /* --- debug / status information --- */
       /* noop */
    }else{
      constexpr size_t kNApvChannels{128};
      Int_t igeo{}, ich{}, idx{};
      constexpr std::array<UShort_t, 16> map_orig{
						  0,  1,  2,  3,
						  12, 13, 14, 15,
						  8,  9, 10, 11,
						  4,  5,  6,  7
      };
      constexpr std::array<UShort_t, 16> map_h424{
						  0,  1,  2,  3,
						  12, 13, 14, 15,
						  8,  9, 10, 11,
						  4,  5,  6,  7
      };
      
      switch(fChMode) {
      case EChannelNumberingMode::kOriginal:
	igeo = (sector << 24) | (adcm << 16) | apv;

	if(sector%2 == 0){
	  ich = map_orig[apv] * kNApvChannels + channel;
	}else{
	  ich = ((map_orig[apv]+12)%16 )* kNApvChannels + channel;      
	}
	idx = ich;
	break;
      case EChannelNumberingMode::kH424:
	igeo = sector;
	if(sector%2 == 0){ // X
	  ich = map_h424[apv] * kNApvChannels + channel;
	}else{ // Y
	  ich = ((map_h424[apv]+12)%16 )* kNApvChannels + channel;      
	}
	idx = ich;
	break;
      case EChannelNumberingMode::kTripE6:
	// sector: 2 (Y1 (Upper)) , 3 (Y1 (Middle)), 4 (X2 (Lower))
	// adcm: always 7
	// apv: Y1 => 0,1,2,4,5,6, X2 => 0,1,2,3,4,5,6,7
	igeo = sector;
	constexpr size_t kNApv{8};
	if (sector < 4 && apv > 2) --apv;
	ich = apv * kNApvChannels + channel;
	idx = (igeo - 2) * kNApv * kNApvChannels + ich;
	break;
      }
              
      //      printf("sec %d, adcm %d , apv %d, igeo %d, ich %d, idx %d: adcval %d\n",sector,adcm,apv,igeo, ich, idx, adcVal);
      
      if (fHitData->GetEntriesFast() <= idx || !fHitData->At(idx)) {
	// if no data object is available, create one
	RICHADCMRaw_t *obj = static_cast<RICHADCMRaw_t*>(this->New());
	obj->SetSegInfo(seg->GetUniqueID(),igeo,ich);
	fHitData->AddAtAndExpand(obj,idx);
	seg->Add(obj);
      }

      data = static_cast<RICHADCMRaw_t*>(fHitData->At(idx));
      data->Set( adcVal );
      fHitData->AddAt(NULL,idx);
    }

     dataidx ++ ;
     if(datanum == dataidx){
       datanum = 0;
       continue;
     }

    // do not use edge
    //rdata->SetEdge(edge == 1 ? 1 : 0);
  }
  
//   // 100MHz clock / timestamp information
//   igeo = 0x10000000;
//   off = apvsize + 14;
//   z = Endian(evtdata[off]);
//   if((z & 0xffff0000) == 0x0aaa0000){
//     adcVal = z & 0x0000ffff;
//     channel = 0;
//     TArtRawDataObject *rdata0 = new TArtRawDataObject(igeo,channel,adcVal);
//     rawseg->PutData(rdata0);
//     //TArtCore::Info(__FILE__,"  100MHz0 0x%08x %d\n", z, adcVal);
//
//     adcVal = Endian(evtdata[off+1]);
//     channel = 1;
//     TArtRawDataObject *rdata1 = new TArtRawDataObject(igeo,channel,adcVal);
//     rawseg->PutData(rdata1);
//     //TArtCore::Info(__FILE__,"  100MHz1 0x%08x \n", z, adcVal);
//   }
//
//   z = Endian(evtdata[off+2]);
//   if((z & 0xffff0000) == 0x1bbb0000){
//     adcVal = z & 0x0000ffff;
//     channel = 2;
//     TArtRawDataObject *rdata2 = new TArtRawDataObject(igeo,channel,adcVal);
//     rawseg->PutData(rdata2);
//     //TArtCore::Info(__FILE__,"  ts0 0x%08x \n", z);
//
//     adcVal = Endian(evtdata[off+3]);
//     channel = 3;
//     TArtRawDataObject *rdata3 = new TArtRawDataObject(igeo,channel,adcVal);
//     rawseg->PutData(rdata3);
//
//     //TArtCore::Info(__FILE__,"  ts1 0x%08x \n", z);
//   }
//
  return 0;
}
