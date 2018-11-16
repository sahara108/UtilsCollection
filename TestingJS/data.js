const setData = (...args) => {
  console.log('setData')
  return 'setData';
}

const getData = () => {
  console.log('getData')
  return {
    name: 'test',
    version: '1.0.0',
  };
}

console.log('script load');
