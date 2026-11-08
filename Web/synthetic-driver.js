/* Presenter-only harness. Enable explicitly with ?presenter=1. No live feeds. */
if(new URLSearchParams(location.search).get('presenter')==='1'){
 const panel=document.createElement('aside');panel.setAttribute('aria-label','Presenter controls');panel.style.cssText='padding:18px;border-top:2px solid #225E79;background:#E9F0F1;color:#173247';panel.innerHTML='<strong>Presenter controls · Synthetic data</strong> <select aria-label="Synthetic fixture" id="fixture">'+Object.entries(J.fixtures).map(([id,f])=>`<option value="${id}">${f.name}</option>`).join('')+'</select> <button id="load-fixture">Load / reset</button> <button id="step-fixture">Step event</button> <button id="age-fixture">Advance 20 min</button><p>Route times and disruptions are demonstration values. Controls do not appear in the traveller view.</p>';document.body.append(panel);
 function update(){journeyState=activeDriver.state;state.scenario=journeyState.gate==='108A'?'change':'connection';render();}
 panel.querySelector('#load-fixture').onclick=()=>{activeDriver=J.driver(panel.querySelector('#fixture').value);state.routeStep=0;state.routeActive=false;update();};
 panel.querySelector('#step-fixture').onclick=()=>{if(!activeDriver)activeDriver=J.driver(panel.querySelector('#fixture').value);activeDriver.step();update();};
 panel.querySelector('#age-fixture').onclick=()=>{if(!activeDriver)activeDriver=J.driver(panel.querySelector('#fixture').value);activeDriver.advance(20);update();};
}
