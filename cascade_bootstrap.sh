#!/bin/bash
set -e

echo "🚀 Bootstrap Cascade MVP avec NestJS + Expo (SQLite)"

# Création du workspace pnpm
echo 'packages:
  - apps/*
  - packages/*' > pnpm-workspace.yaml

mkdir -p apps/api apps/app

######################################
# 1) Backend API (NestJS + Prisma)
######################################
cd apps/api
pnpm dlx @nestjs/cli new . --package-manager=pnpm --skip-git
pnpm add prisma @prisma/client pino pino-pretty zod
pnpm dlx prisma init --datasource-provider sqlite

# Prisma schema
cat > prisma/schema.prisma <<'PRISMA'
generator client { provider = "prisma-client-js" }
datasource db { provider = "sqlite"; url = "file:./dev.db" }

model Pot {
  id              String  @id @default(cuid())
  name            String
  targetAmount    Int
  initialAmount   Int
  endDate         DateTime
  collectedAmount Int     @default(0)
  status          String  @default("open")
  slug            String  @unique
  ownerTokenHash  String
  createdAt       DateTime @default(now())
  contributions   Contribution[]
}

model Contribution {
  id           String  @id @default(cuid())
  potId        String
  amountPaid   Int
  status       String  @default("PENDING")
  email        String?
  contribToken String  @unique
  createdAt    DateTime @default(now())
  @@index([potId])
}
PRISMA

# Controller santé + cagnottes
cat > src/health.controller.ts <<'TS'
import { Controller, Get } from '@nestjs/common';
@Controller() export class HealthController {
  @Get('health') ping(){ return { ok:true }; }
}
TS

cat > src/pots.controller.ts <<'TS'
import { Controller, Get, Post, Body, Param } from '@nestjs/common';
import { PrismaClient } from '@prisma/client';
const db = new PrismaClient();

@Controller('pots')
export class PotsController {
  @Post() async create(@Body() dto:any){
    const slug = dto.name.toLowerCase().replace(/\s+/g,'-') + '-' + Math.random().toString(36).slice(2,6);
    const pot = await db.pot.create({
      data: {
        name: dto.name,
        targetAmount: +dto.targetAmountCents,
        initialAmount: +dto.initialAmountCents,
        endDate: new Date(dto.endDateISO),
        slug,
        ownerTokenHash: 'hash:' + Math.random().toString(36).slice(2),
      }
    });
    return pot;
  }

  @Get(':slug') async get(@Param('slug') slug:string){
    const pot = await db.pot.findUnique({ where:{ slug }, include:{ contributions:true }});
    if(!pot) return { error:'not_found' };
    const participants = pot.contributions.filter(c=>c.status==='CONFIRMED').length;
    const currentAmountToPayCents = pot.collectedAmount < pot.targetAmount
      ? pot.initialAmount
      : Math.ceil(pot.targetAmount / (participants+1));
    return { name:pot.name, target:pot.targetAmount, collected:pot.collectedAmount,
      participants, endsAt:pot.endDate, status:pot.status, currentAmountToPayCents };
  }
}
TS

# Injection controllers
sed -i.bak "1s;^;import { HealthController } from './health.controller';\nimport { PotsController } from './pots.controller';\n;" src/app.module.ts
sed -i.bak "s/controllers: \[AppController\]/controllers: [AppController, HealthController, PotsController]/" src/app.module.ts

# Migration DB
pnpm dlx prisma migrate dev --name init

cd ../../

######################################
# 2) Frontend App (Expo + Web)
######################################
cd apps/app
pnpm dlx create-expo-app . --template blank --yes
pnpm add @tanstack/react-query

mkdir -p app/c
cat > app/index.tsx <<'TSX'
import { Text, View, Pressable } from 'react-native';
import { Link } from 'expo-router';
export default function Home(){
  return <View style={{padding:24}}>
    <Text style={{fontSize:22, fontWeight:'600'}}>Cascade — démo</Text>
    <Link href="/create" asChild><Pressable style={{marginTop:20}}><Text>Créer une cagnotte</Text></Pressable></Link>
  </View>;
}
TSX

mkdir -p app/create
cat > app/create/index.tsx <<'TSX'
import { useState } from 'react';
import { View, Text, TextInput, Pressable } from 'react-native';
export default function Create(){
  const [name,setName]=useState('Pizza Party');
  const [target,setTarget]=useState('10000');
  const [initial,setInitial]=useState('1000');
  const [end,setEnd]=useState(new Date(Date.now()+86400000).toISOString());
  const submit=async()=>{
    const r=await fetch(process.env.EXPO_PUBLIC_API_URL+'/pots',{
      method:'POST',headers:{'Content-Type':'application/json'},
      body:JSON.stringify({name,targetAmountCents:+target,initialAmountCents:+initial,endDateISO:end})
    });
    const pot=await r.json(); location.href='/c/'+pot.slug;
  };
  return <View style={{padding:24,gap:8}}>
    <Text style={{fontSize:18}}>Créer une cagnotte</Text>
    <TextInput placeholder="Nom" value={name} onChangeText={setName} />
    <TextInput placeholder="Objectif (cents)" value={target} onChangeText={setTarget} keyboardType="numeric" />
    <TextInput placeholder="Montant fixe (cents)" value={initial} onChangeText={setInitial} keyboardType="numeric" />
    <TextInput placeholder="Fin (ISO)" value={end} onChangeText={setEnd} />
    <Pressable onPress={submit} style={{padding:12, backgroundColor:'#eee', marginTop:8}}><Text>Créer</Text></Pressable>
  </View>;
}
TSX

cat > app/c/[slug].tsx <<'TSX'
import { useLocalSearchParams } from 'expo-router';
import { useEffect, useState } from 'react';
import { View, Text } from 'react-native';
export default function Pot(){
  const { slug } = useLocalSearchParams();
  const [d,setD]=useState<any>(null);
  useEffect(()=>{ fetch(process.env.EXPO_PUBLIC_API_URL+'/pots/'+slug).then(r=>r.json()).then(setD); },[slug]);
  if(!d) return <Text>...</Text>;
  return <View style={{padding:24,gap:8}}>
    <Text style={{fontSize:22,fontWeight:'600'}}>{d.name}</Text>
    <Text>{d.collected/100}€ / {d.target/100}€ — {d.participants} participants</Text>
    <Text>À payer maintenant : {(d.currentAmountToPayCents/100).toFixed(2)}€</Text>
  </View>;
}
TSX

cat > .env <<'ENV'
EXPO_PUBLIC_API_URL=http://localhost:3000
ENV

cd ../../

echo "✅ Bootstrap terminé."
echo "Démarre avec :"
echo "  1) API: cd apps/api && pnpm run start:dev"
echo "  2) App: cd apps/app && pnpm run web"
