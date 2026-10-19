// @vitest-environment jsdom
import React,{useState} from 'react';
import {afterEach,beforeEach,describe,it,expect,vi} from 'vitest';
import {render,screen,cleanup} from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import GamePicker,{type GameSelection} from '../src/GamePicker';

function Flow(){
 const[selection,setSelection]=useState<GameSelection>({sport:'',city:'',location:''});
 return <GamePicker selection={selection} sports={['volleyball','badminton']} cities={selection.sport==='volleyball'?['Toronto','London']:['Kitchener']} locations={selection.city==='Toronto'?['College Français']:selection.city==='London'?['La Pommeraie']:['David Saint Jacques']} onChange={setSelection}><p>Sessions for {selection.sport} in {selection.city} at {selection.location}</p><button>Going</button></GamePicker>;
}
beforeEach(()=>{Element.prototype.scrollIntoView=vi.fn()});
afterEach(()=>{cleanup();vi.restoreAllMocks()});

describe('Drop-in game selection',()=>{
 it('replaces each menu with the next step and moves focus to it',async()=>{
  const user=userEvent.setup();render(<Flow/>);
  await user.click(screen.getByRole('button',{name:'volleyball'}));
  expect(screen.queryByRole('button',{name:'badminton'})).toBeNull();
  expect(screen.getByRole('heading',{name:'Choose your city'})).toBe(document.activeElement);
  expect(screen.queryByRole('button',{name:'College Français'})).toBeNull();
  await user.click(screen.getByRole('button',{name:'Toronto'}));
  expect(screen.queryByRole('button',{name:'London'})).toBeNull();
  expect(screen.getByRole('heading',{name:'Choose your location'})).toBe(document.activeElement);
  await user.click(screen.getByRole('button',{name:'College Français'}));
  expect(screen.getByRole('heading',{name:'Available sessions'})).toBe(document.activeElement);
  expect(screen.getByText('Sessions for volleyball in Toronto at College Français')).toBeTruthy();
  expect(screen.getByRole('button',{name:'Going'})).toBeTruthy();
  expect(Element.prototype.scrollIntoView).toHaveBeenCalledTimes(3);
 });
 it('lets players go back, choose a different city, and return to all sports',async()=>{
  const user=userEvent.setup();render(<Flow/>);
  await user.click(screen.getByRole('button',{name:'volleyball'}));
  await user.click(screen.getByRole('button',{name:'Toronto'}));
  await user.click(screen.getByRole('button',{name:'College Français'}));
  await user.click(screen.getByRole('button',{name:/Back/}));
  expect(screen.getByRole('button',{name:'College Français'})).toBeTruthy();
  expect(screen.queryByRole('button',{name:'Going'})).toBeNull();
  await user.click(screen.getByRole('button',{name:/Back/}));
  await user.click(screen.getByRole('button',{name:'London'}));
  expect(screen.queryByRole('button',{name:'College Français'})).toBeNull();
  await user.click(screen.getByRole('button',{name:'La Pommeraie'}));
  expect(screen.getByText('Sessions for volleyball in London at La Pommeraie')).toBeTruthy();
  await user.click(screen.getByRole('button',{name:/All Sports/}));
  expect(screen.getByRole('heading',{name:'Choose your sport'})).toBeTruthy();
  await user.click(screen.getByRole('button',{name:'badminton'}));
  expect(screen.getByRole('button',{name:'Kitchener'})).toBeTruthy();
  expect(screen.queryByText(/La Pommeraie/)).toBeNull();
  expect(screen.queryByRole('button',{name:'Going'})).toBeNull();
 });
 it('offers a way out when a selected sport has no available cities',async()=>{
  const user=userEvent.setup();const onChange=vi.fn();
  render(<GamePicker selection={{sport:'volleyball',city:'',location:''}} sports={['volleyball']} cities={[]} locations={[]} onChange={onChange}><p>Sessions</p></GamePicker>);
  expect(screen.getByText(/No cities are currently available/)).toBeTruthy();
  await user.click(screen.getByRole('button',{name:/All Sports/}));
  expect(onChange).toHaveBeenCalledWith({sport:'',city:'',location:''});
 });
});
